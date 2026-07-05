# ── Firedancer Packet Generation ─────────────────────
# `pktfd` runs the current binary's pktgen; `pktfd setup` prepares a physical-
# loopback test rig. Relies on _fdbin/_fdbinpath/_fdconfig/_fd_dispatch from
# firedancer.zsh and firedancer-config.zsh.
#
# `pktfd setup` prompts for each NIC only when it's actually needed: the
# firedancer NIC up front, the DPDK pktgen NIC only after you've said you
# want to start pktgen. Picks are saved per-machine (untracked) — Enter
# keeps the last one.
#
# This file also defines the DPDK/NIC helpers floodfd.zsh reuses for its own
# `floodfd dpdk` engine (_fd_pick_iface, _fd_is_mellanox, _fd_lcore_plan,
# _fd_check_numa, _fd_reserve_hugepages, _fd_vfio_bind/_fd_vfio_restore) —
# both drive DPDK pktgen the same way, just against a loopback peer vs. a
# target over the wire.

PKTFD_IFACES_FILE="$HOME/.config/dotfiles/pktfd-ifaces"
_pktfd_fdif() { grep '^fdif=' "$PKTFD_IFACES_FILE" 2>/dev/null | cut -d= -f2-; }
_pktfd_pgif() { grep '^pgif=' "$PKTFD_IFACES_FILE" 2>/dev/null | cut -d= -f2-; }
_pktfd_setif() {
    local key=$1 val=$2
    mkdir -p "$(dirname "$PKTFD_IFACES_FILE")"
    local fd=$(_pktfd_fdif) pg=$(_pktfd_pgif)
    [ "$key" = fdif ] && fd=$val
    [ "$key" = pgif ] && pg=$val
    printf 'fdif=%s\npgif=%s\n' "$fd" "$pg" > "$PKTFD_IFACES_FILE"
}

function pktfd() {
    if [ "$1" = setup ];   then shift; _pktfd_setup "$@";   return; fi
    if [ "$1" = restore ]; then shift; _pktfd_restore "$@"; return; fi
    if [ "$1" = gdb ];     then shift; sudo gdb -q --args "$(_fdbinpath)" pktgen --config "$(_fdconfig)" "$@"; return; fi
    _fd_dispatch "$1" sudo "$(_fdbinpath)" pktgen --config "$(_fdconfig)"
}

# ── Shared DPDK/NIC Helpers (pktfd + floodfd) ────────

# _fd_pick_iface <prefix> <label> [current]: list network interfaces and
# prompt for one, printing the choice to stdout. Enter keeps [current] if given.
function _fd_pick_iface() {
    local prefix=$1 label=$2 cur=$3
    local ifaces=() i idx=1 drv
    echo "Available interfaces:" >&2
    for i in /sys/class/net/*(N); do
        i=${i##*/}
        [ "$i" = lo ] && continue
        drv=$(basename "$(readlink -f /sys/class/net/$i/device/driver 2>/dev/null)" 2>/dev/null)
        ifaces+=("$i")
        printf "  %d) %-20s %s\n" "$idx" "$i" "${drv:+driver: $drv}" >&2
        idx=$((idx + 1))
    done
    [ ${#ifaces} -eq 0 ] && { echo "$prefix: no network interfaces found." >&2; return 1; }

    local sel
    read "sel?${label}${cur:+ (Enter = keep '$cur')} [1-${#ifaces}]: "
    if [ -z "$sel" ]; then
        [ -z "$cur" ] && { echo "$prefix: no interface selected." >&2; return 1; }
        echo "$cur"
        return 0
    fi
    if ! [[ "$sel" =~ '^[0-9]+$' ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#ifaces} ]; then
        echo "$prefix: invalid selection '$sel'." >&2
        return 1
    fi
    echo "${ifaces[$sel]}"
}

# _fd_is_mellanox <iface> <curdrv>: detects (and lets the user confirm/
# override) whether <iface> is a bifurcated Mellanox PMD — DPDK drives it
# while it stays on the kernel driver, so it never needs a vfio-pci rebind.
function _fd_is_mellanox() {
    local iface=$1 curdrv=$2 mellanox=0
    case "$curdrv" in mlx5_core|mlx5) mellanox=1 ;; esac
    local defans; [ "$mellanox" = 1 ] && defans=Y || defans=N
    [ -n "$curdrv" ] && echo "Detected kernel driver for $iface: $curdrv"
    local ans
    read "ans?Mellanox/mlx5 NIC (no vfio-pci rebind needed)? [$defans]: "
    ans=${ans:-$defans}
    case "$ans" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

# _fd_lcore_plan <prefix> <ntx>: lays out DPDK lcores top-down (fits a
# 16-core box): main 15 | RX 14 | TX 13, 12, ... Every core past the main
# and RX cores is a dedicated TX (generation) core, and TX throughput scales
# with their count. DPDK would otherwise default the main lcore to the
# lowest core in -l (a TX core here), so it's pinned explicitly with
# --main-lcore. On success prints "<main> <rxcore> <txlo> <txrange> <lcores>
# <map> <est>" to stdout; on failure (machine too small, or <ntx> would run
# past core 0) prints an error prefixed with <prefix> and returns 1.
function _fd_lcore_plan() {
    local prefix=$1 ntx=$2
    local main=15 rxcore=14 txhi=13
    local txlo=$((txhi - ntx + 1))
    if [ ! -d "/sys/devices/system/cpu/cpu$main" ]; then
        echo "$prefix: layout needs at least 16 cores (uses up to core $main); machine has $(nproc)." >&2
        return 1
    fi
    if [ "$txlo" -lt 0 ]; then
        echo "$prefix: $ntx TX cores would run past core 0 (lowest = $txlo). Choose fewer." >&2
        return 1
    fi
    local lcores="${txlo}-${main}"
    local txrange="$txhi"
    [ "$txlo" -lt "$txhi" ] && txrange="${txlo}-${txhi}"
    local map="[${rxcore}:${txrange}].0"
    local est=$((ntx * 30))
    echo "$main $rxcore $txlo $txrange $lcores $map $est"
}

# _fd_check_numa <prefix> <iface> <nicnode> <lo> <hi>: warns if any core in
# [lo, hi] isn't on the NIC's NUMA node — cross-socket DMA skews throughput.
function _fd_check_numa() {
    local prefix=$1 iface=$2 nicnode=$3 lo=$4 hi=$5
    if [ -z "$nicnode" ] || [ "$nicnode" = "-1" ]; then return 0; fi
    local c cnode badcores n
    for c in {$lo..$hi}; do
        cnode=""
        for n in /sys/devices/system/cpu/cpu$c/node*(N); do cnode=${n##*/node}; done
        [ -n "$cnode" ] && [ "$cnode" != "$nicnode" ] && badcores="${badcores} $c"
    done
    if [ -n "$badcores" ]; then
        echo "$prefix: WARNING — $iface is on NUMA node $nicnode but core(s)$badcores are on another node."
        echo "  Cross-socket DMA will skew results; pin to cores on node $nicnode for accurate numbers."
    fi
}

# _fd_reserve_hugepages <ntx>: reserves 1024 x 2MB hugepages per TX core and
# mounts a 2MB hugetlbfs at /mnt/huge if one isn't already mounted.
function _fd_reserve_hugepages() {
    local ntx=$1
    local npages=$(( 1024 * ntx ))
    echo "Reserving $npages x 2MB hugepages ($((npages * 2)) MiB)..."
    echo "$npages" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null
    if ! grep -q 'hugetlbfs.*pagesize=2M' /proc/mounts; then
        sudo mkdir -p /mnt/huge && sudo mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge
    fi
}

# _fd_vfio_bind <tool> <iface> <pci> <curdrv> <statefile> [peer] [ip]: binds
# <iface> to vfio-pci for DPDK and records pci/drv/if/ip/peer in <statefile>
# so _fd_vfio_restore can undo it later. <tool> names the command that hints
# how to restore (e.g. "pktfd", "floodfd"). Only call this for non-Mellanox
# NICs (see _fd_is_mellanox) — Mellanox never needs rebinding.
function _fd_vfio_bind() {
    local tool=$1 iface=$2 pci=$3 curdrv=$4 state=$5 peer=$6 ip=$7
    echo "Binding $iface ($pci, ${curdrv:-unknown}) to vfio-pci for DPDK..."
    sudo modprobe vfio-pci 2>/dev/null
    if ! ls /sys/kernel/iommu_groups/* >/dev/null 2>&1; then
        echo "  NOTE: no IOMMU groups found. vfio-pci needs an IOMMU (boot with 'intel_iommu=on iommu=pt'),"
        echo "        or enable no-IOMMU mode: echo 1 | sudo tee /sys/module/vfio/parameters/enable_unsafe_noiommu_mode"
    fi
    if command -v dpdk-devbind.py >/dev/null 2>&1; then
        sudo dpdk-devbind.py --bind=vfio-pci "$pci"
    else
        echo vfio-pci | sudo tee "/sys/bus/pci/devices/$pci/driver_override" >/dev/null
        [ -e "/sys/bus/pci/devices/$pci/driver" ] && \
            echo "$pci" | sudo tee "/sys/bus/pci/devices/$pci/driver/unbind" >/dev/null
        echo "$pci" | sudo tee /sys/bus/pci/drivers_probe >/dev/null
    fi
    printf 'pci=%s\ndrv=%s\nif=%s\nip=%s\npeer=%s\n' "$pci" "$curdrv" "$iface" "$ip" "$peer" > "$state"
    echo "  To rebind the kernel driver + restore $iface later:  $tool restore"
}

# _fd_vfio_restore <prefix> <statefile>: undoes _fd_vfio_bind — rebinds the
# interface to its kernel driver, renames the reborn netdev back, restores
# its IP, and bounces a peer interface if one was recorded (pktfd's loopback
# rig needs the far end bounced to re-establish carrier).
function _fd_vfio_restore() {
    local prefix=$1 state=$2
    if [ ! -f "$state" ]; then
        echo "$prefix: no saved state ($state) — nothing was bound to vfio-pci."
        return 1
    fi

    local pci drv iface ip peer k v
    while IFS='=' read -r k v; do
        case "$k" in
            pci) pci=$v ;; drv) drv=$v ;;
            if)  iface=$v ;; ip) ip=$v ;; peer) peer=$v ;;
        esac
    done < "$state"
    if [ -z "$pci" ]; then
        echo "$prefix: state file is malformed; remove $state and re-run setup."
        return 1
    fi

    echo "Rebinding $pci to kernel driver '${drv:-?}'..."
    if command -v dpdk-devbind.py >/dev/null 2>&1 && [ -n "$drv" ]; then
        sudo dpdk-devbind.py --bind="$drv" "$pci"
    else
        echo "$pci" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind >/dev/null 2>&1
        echo "" | sudo tee "/sys/bus/pci/devices/$pci/driver_override" >/dev/null
        if [ -n "$drv" ] && [ -d "/sys/bus/pci/drivers/$drv" ]; then
            echo "$pci" | sudo tee "/sys/bus/pci/drivers/$drv/bind" >/dev/null 2>&1
        fi
        echo "$pci" | sudo tee /sys/bus/pci/drivers_probe >/dev/null 2>&1
    fi

    # The kernel re-creates the netdev under a fresh name; rename it back.
    local newname n
    for n in /sys/bus/pci/devices/$pci/net/*(N); do newname=${n##*/}; done
    if [ -z "$newname" ]; then
        echo "$prefix: device rebound but no netdev appeared for $pci."
        echo "  Check 'ip link'; you may need to re-run, or driver '$drv' failed to attach."
        return 1
    fi
    iface=${iface:-$newname}
    if [ "$newname" != "$iface" ]; then
        echo "Renaming '$newname' -> '$iface'..."
        sudo ip link set "$newname" down && \
        sudo ip link set "$newname" name "$iface"
    fi
    sudo ip link set "$iface" up

    if [ -n "$ip" ] && ! ip -4 -o addr show dev "$iface" | grep -q "${ip%%/*}"; then
        echo "Re-adding $ip to $iface (lost when the netdev was destroyed)..."
        sudo ip addr add "$ip" dev "$iface"
    fi
    if [ -n "$peer" ] && ip link show "$peer" >/dev/null 2>&1; then
        echo "Bouncing $peer to re-establish carrier on the loopback link..."
        sudo ip link set "$peer" down && sudo ip link set "$peer" up
    fi

    rm -f "$state"
    echo "Done — $iface is back on the kernel driver."
    [ -n "$peer" ] && echo "  $peer link restored."
}

# pktfd setup: point the firedancer NIC at the peer (route + static ARP), then
# optionally launch DPDK pktgen on the pktgen NIC aimed back at it. Works with
# any DPDK-supported NIC — Mellanox (mlx5, bifurcated) needs no rebind, while
# others must be bound to vfio-pci for pktgen.
function _pktfd_setup() {
    local fdif
    fdif=$(_fd_pick_iface "pktfd" "Firedancer NIC" "$(_pktfd_fdif)") || return 1
    _pktfd_setif fdif "$fdif"

    if ! ip link show "$fdif" >/dev/null 2>&1; then
        echo "pktfd setup: firedancer interface '$fdif' not found."
        return 1
    fi

    # Offer a /30 link address on the firedancer NIC if it has none.
    local ans
    if ! ip -4 -o addr show dev "$fdif" | grep -q .; then
        read "ans?$fdif has no IPv4. Assign 169.254.1.1/30? [Y/n] "
        case "$ans" in
            n|N|no|No) ;;
            *) sudo ip addr add 169.254.1.1/30 dev "$fdif" && echo "  assigned 169.254.1.1/30 to $fdif" ;;
        esac
    fi

    echo "Configuring $fdif route + static neighbor for the firedancer peer..."
    sudo ip r replace 10.181.80.14 dev "$fdif"
    sudo ip n replace 10.181.80.14 lladdr aa:aa:aa:aa:aa:aa dev "$fdif"

    read "ans?Also start DPDK pktgen? [y/N] "
    case "$ans" in
        y|Y|yes|Yes) ;;
        *) echo "Done — firedancer $fdif setup only."; return 0 ;;
    esac

    local pgif
    pgif=$(_fd_pick_iface "pktfd" "Pktgen NIC" "$(_pktfd_pgif)") || return 1
    _pktfd_setif pgif "$pgif"

    # How many TX (generation) cores? More cores -> more Mpps, up to NIC line rate.
    local ntx
    echo "DPDK uses 1 lcore for control + 1 for RX; each extra TX core adds ~30 Mpps (64B)."
    read "ntx?How many TX (generation) cores? [1] "
    ntx=${ntx:-1}
    if ! [[ "$ntx" =~ '^[0-9]+$' ]] || [ "$ntx" -lt 1 ]; then
        echo "pktfd setup: invalid TX core count '$ntx'."
        return 1
    fi

    local plan main rxcore txlo txrange lcores map est
    plan=$(_fd_lcore_plan "pktfd setup" "$ntx") || return 1
    read -r main rxcore txlo txrange lcores map est <<< "$plan"

    if ! ip link show "$pgif" >/dev/null 2>&1; then
        echo "pktfd setup: pktgen interface '$pgif' not found."
        return 1
    fi
    if ! command -v pktgen >/dev/null 2>&1; then
        echo "pktfd setup: WARNING — DPDK/pktgen does not appear to be installed."
        return 1
    fi

    # Capture pgif's PCI address, NUMA node, kernel driver, and IP now — binding
    # to vfio-pci destroys the netdev, so /sys/class/net/$pgif disappears.
    local pci nicnode curdrv pgip
    pci=$(basename "$(readlink -f /sys/class/net/$pgif/device)")
    nicnode=$(cat /sys/class/net/$pgif/device/numa_node 2>/dev/null)
    curdrv=$(basename "$(readlink -f /sys/class/net/$pgif/device/driver)" 2>/dev/null)
    pgip=$(ip -4 -o addr show dev "$pgif" | awk '{print $4}' | head -1)

    if [ -z "$pgip" ]; then
        read "ans?$pgif has no IPv4. Assign 169.254.1.2/30? [Y/n] "
        case "$ans" in
            n|N|no|No) ;;
            *) sudo ip addr add 169.254.1.2/30 dev "$pgif" && pgip="169.254.1.2/30" ;;
        esac
    fi

    local mellanox=0
    _fd_is_mellanox "$pgif" "$curdrv" && mellanox=1

    # Aim pktgen at fdif: its MAC and its IPv4.
    local dstmac dstip
    dstmac=$(cat /sys/class/net/$fdif/address)
    dstip=$(ip -4 -o addr show dev "$fdif" | awk '{print $4}' | head -1 | cut -d/ -f1)
    if [ -z "$dstip" ]; then
        echo "pktfd setup: $fdif has no IPv4 — assign one first."
        return 1
    fi

    _fd_check_numa "pktfd setup" "$pgif" "$nicnode" "$txlo" "$main"

    echo "DPDK pktgen core plan on $pgif:"
    echo "  $main    main lcore (DPDK control/CLI — no traffic)"
    echo "  $rxcore    RX core"
    echo "  $txrange  TX core(s) x$ntx  ->  ~${est} Mpps max (rough 30 Mpps/core guide, capped by NIC line rate)"

    _fd_reserve_hugepages "$ntx"

    [ "$mellanox" != 1 ] && _fd_vfio_bind pktfd "$pgif" "$pci" "$curdrv" /tmp/pktfd-bound "$fdif" "$pgip"

    local cmds=/tmp/pktfd-setup.pkt
    cat > "$cmds" <<EOF
set 0 dst mac $dstmac
set 0 dst ip $dstip
set 0 proto udp
set 0 dport 9000
set 0 size 64
disable 0 vlan
set 0 src ip ${pgip:-169.254.1.2/30}
EOF

    echo "Launching pktgen on $pgif ($pci) -> $fdif ($dstip / $dstmac), lcores $lcores (main $main)..."
    sudo pktgen -l "$lcores" -n 4 -a "$pci" --main-lcore "$main" -- -m "$map" -f "$cmds"
}

# pktfd restore: undo a vfio-pci bind from `pktfd setup` — rebind the pktgen NIC
# to its kernel driver and rename the reborn netdev, so the next `pktfd setup`
# finds it. (Mellanox runs never bind, so there's nothing to restore.)
function _pktfd_restore() { _fd_vfio_restore "pktfd restore" /tmp/pktfd-bound; }
