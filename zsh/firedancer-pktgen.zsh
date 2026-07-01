# ── Firedancer Packet Generation ─────────────────────
# `pktfd` runs the current binary's pktgen; `pktfd setup` prepares a physical-
# loopback test rig. Relies on _fdbin/_fdbinpath/_fdconfig from firedancer.zsh
# and firedancer-config.zsh.
#
# Use `pktfd ifs` to configure which NICs to use (saved per-machine, untracked).

# DPDK's "main" lcore runs control/CLI and generates no traffic; pktgen also
# needs one core to service RX. Every remaining core is a dedicated TX
# (generation) core, and TX throughput scales with their count. Cores are
# allotted top-down so it fits a 16-core box (cores 0-15):
#   main 15 | RX 14 | TX 13, 12, 11, ...
# DPDK would otherwise default the main lcore to the lowest core in -l (a TX
# core here), so we pin it explicitly with --main-lcore.

PKTFD_IFACES_FILE="$HOME/.config/dotfiles/pktfd-ifaces"
_pktfd_fdif() { grep '^fdif=' "$PKTFD_IFACES_FILE" 2>/dev/null | cut -d= -f2-; }
_pktfd_pgif() { grep '^pgif=' "$PKTFD_IFACES_FILE" 2>/dev/null | cut -d= -f2-; }

function pktfd() {
    if [ "$1" = setup ];   then shift; _pktfd_setup "$@";   return; fi
    if [ "$1" = restore ]; then shift; _pktfd_restore "$@"; return; fi
    if [ "$1" = ifs ];     then shift; _pktfd_ifs "$@";     return; fi
    sudo "$(_fdbinpath)" pktgen --config "$(_fdconfig)"
}

# pktfd ifs [fdif pgif]: select (or display) the firedancer and pktgen interfaces.
# With no args: interactive selection from a numbered list.
# With two args: direct assignment — pktfd ifs <fdif> <pgif>.
function _pktfd_ifs() {
    mkdir -p "$(dirname "$PKTFD_IFACES_FILE")"

    if [ $# -eq 2 ]; then
        printf 'fdif=%s\npgif=%s\n' "$1" "$2" > "$PKTFD_IFACES_FILE"
        echo "pktfd interfaces: firedancer=$1  pktgen=$2"
        return 0
    fi

    local cur_fd cur_pg ans
    cur_fd=$(_pktfd_fdif)
    cur_pg=$(_pktfd_pgif)

    if [ -n "$cur_fd" ] && [ -n "$cur_pg" ]; then
        echo "Current pktfd interfaces: firedancer=$cur_fd  pktgen=$cur_pg"
        read "ans?Change? [y/N] "
        case "$ans" in y|Y|yes|Yes) ;; *) return 0 ;; esac
    fi

    local ifaces=() i idx=1 drv
    echo "Available interfaces:"
    for i in /sys/class/net/*(N); do
        i=${i##*/}
        [ "$i" = lo ] && continue
        drv=$(basename "$(readlink -f /sys/class/net/$i/device/driver 2>/dev/null)" 2>/dev/null)
        ifaces+=("$i")
        printf "  %d) %-20s %s\n" "$idx" "$i" "${drv:+driver: $drv}"
        idx=$((idx + 1))
    done
    [ ${#ifaces} -eq 0 ] && { echo "pktfd ifs: no network interfaces found."; return 1; }

    local sel fdif="$cur_fd" pgif="$cur_pg"

    read "sel?Firedancer NIC${cur_fd:+ (Enter = keep '$cur_fd')} [1-${#ifaces}]: "
    if [ -n "$sel" ]; then
        if ! [[ "$sel" =~ '^[0-9]+$' ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#ifaces} ]; then
            echo "pktfd ifs: invalid selection '$sel'."
            return 1
        fi
        fdif=${ifaces[$sel]}
    fi
    [ -z "$fdif" ] && { echo "pktfd ifs: no firedancer interface selected."; return 1; }

    read "sel?Pktgen NIC${cur_pg:+ (Enter = keep '$cur_pg')} [1-${#ifaces}]: "
    if [ -n "$sel" ]; then
        if ! [[ "$sel" =~ '^[0-9]+$' ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#ifaces} ]; then
            echo "pktfd ifs: invalid selection '$sel'."
            return 1
        fi
        pgif=${ifaces[$sel]}
    fi
    [ -z "$pgif" ] && { echo "pktfd ifs: no pktgen interface selected."; return 1; }

    printf 'fdif=%s\npgif=%s\n' "$fdif" "$pgif" > "$PKTFD_IFACES_FILE"
    echo "pktfd interfaces set: firedancer=$fdif  pktgen=$pgif"
}

# pktfd setup: point the firedancer NIC at the peer (route + static ARP), then
# optionally launch DPDK pktgen on the pktgen NIC aimed back at it. Works with
# any DPDK-supported NIC — Mellanox (mlx5, bifurcated) needs no rebind, while
# others must be bound to vfio-pci for pktgen.
function _pktfd_setup() {
    local fdif pgif
    fdif=$(_pktfd_fdif)
    pgif=$(_pktfd_pgif)
    if [ -z "$fdif" ] || [ -z "$pgif" ]; then
        echo "pktfd: interfaces not configured — running 'pktfd ifs' first..."
        echo ""
        _pktfd_ifs || return 1
        fdif=$(_pktfd_fdif)
        pgif=$(_pktfd_pgif)
    fi

    if ! ip link show "$fdif" >/dev/null 2>&1; then
        echo "pktfd setup: firedancer interface '$fdif' not found. Run 'pktfd ifs' to reconfigure."
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

    read "ans?Also start DPDK pktgen on $pgif? [y/N] "
    case "$ans" in
        y|Y|yes|Yes) ;;
        *) echo "Done — firedancer $fdif setup only."; return 0 ;;
    esac

    # How many TX (generation) cores? More cores -> more Mpps, up to NIC line rate.
    local ntx
    echo "DPDK uses 1 lcore for control + 1 for RX; each extra TX core adds ~30 Mpps (64B)."
    read "ntx?How many TX (generation) cores? [1] "
    ntx=${ntx:-1}
    if ! [[ "$ntx" =~ '^[0-9]+$' ]] || [ "$ntx" -lt 1 ]; then
        echo "pktfd setup: invalid TX core count '$ntx'."
        return 1
    fi

    # Lay out lcores top-down (fits a 16-core box): main 15 | RX 14 | TX 13,12,...
    local main=15 rxcore=14 txhi=13
    local txlo=$((txhi - ntx + 1))
    local lcores="${txlo}-${main}"
    local txrange="$txhi"
    [ "$txlo" -lt "$txhi" ] && txrange="${txlo}-${txhi}"
    local map="[${rxcore}:${txrange}].0"
    local est=$((ntx * 30))

    if [ ! -d "/sys/devices/system/cpu/cpu$main" ]; then
        echo "pktfd setup: layout needs at least 16 cores (uses up to core $main); machine has $(nproc)."
        return 1
    fi
    if [ "$txlo" -lt 0 ]; then
        echo "pktfd setup: $ntx TX cores would run past core 0 (lowest = $txlo). Choose fewer."
        return 1
    fi

    if ! ip link show "$pgif" >/dev/null 2>&1; then
        echo "pktfd setup: pktgen interface '$pgif' not found. Run 'pktfd ifs' to reconfigure."
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

    # Mellanox (mlx5) is a bifurcated PMD: DPDK drives it while it stays on the
    # kernel driver, so no rebind needed. Everything else needs vfio-pci.
    local mellanox=0
    case "$curdrv" in mlx5_core|mlx5) mellanox=1 ;; esac
    local defans; [ "$mellanox" = 1 ] && defans=Y || defans=N
    [ -n "$curdrv" ] && echo "Detected kernel driver for $pgif: $curdrv"
    read "ans?Mellanox/mlx5 NIC (no vfio-pci rebind needed)? [$defans]: "
    ans=${ans:-$defans}
    case "$ans" in y|Y|yes|Yes) mellanox=1 ;; *) mellanox=0 ;; esac

    # Aim pktgen at fdif: its MAC and its IPv4.
    local dstmac dstip
    dstmac=$(cat /sys/class/net/$fdif/address)
    dstip=$(ip -4 -o addr show dev "$fdif" | awk '{print $4}' | head -1 | cut -d/ -f1)
    if [ -z "$dstip" ]; then
        echo "pktfd setup: $fdif has no IPv4 — assign one first."
        return 1
    fi

    # Warn if any pktgen core isn't on pgif's NUMA node (cross-socket DMA skews results).
    local c cnode badcores n
    if [ -n "$nicnode" ] && [ "$nicnode" != "-1" ]; then
        for c in {$txlo..$main}; do
            cnode=""
            for n in /sys/devices/system/cpu/cpu$c/node*(N); do cnode=${n##*/node}; done
            [ -n "$cnode" ] && [ "$cnode" != "$nicnode" ] && badcores="${badcores} $c"
        done
        if [ -n "$badcores" ]; then
            echo "pktfd setup: WARNING — $pgif is on NUMA node $nicnode but core(s)$badcores are on another node."
            echo "  Cross-socket DMA will skew results; pin to cores on node $nicnode for accurate numbers."
        fi
    fi

    echo "DPDK pktgen core plan on $pgif:"
    echo "  $main    main lcore (DPDK control/CLI — no traffic)"
    echo "  $rxcore    RX core"
    echo "  $txrange  TX core(s) x$ntx  ->  ~${est} Mpps max (rough 30 Mpps/core guide, capped by NIC line rate)"

    # Reserve 2MB hugepages (1024 per TX core) and mount a 2MB hugetlbfs if needed.
    local npages=$(( 1024 * ntx ))
    echo "Reserving $npages x 2MB hugepages ($((npages * 2)) MiB)..."
    echo "$npages" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null
    if ! grep -q 'hugetlbfs.*pagesize=2M' /proc/mounts; then
        sudo mkdir -p /mnt/huge && sudo mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge
    fi

    if [ "$mellanox" != 1 ]; then
        echo "Binding $pgif ($pci, ${curdrv:-unknown}) to vfio-pci for DPDK..."
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
        printf 'pci=%s\ndrv=%s\npgif=%s\nfdif=%s\npgip=%s\n' \
            "$pci" "$curdrv" "$pgif" "$fdif" "$pgip" > /tmp/pktfd-bound
        echo "  To rebind the kernel driver + restore $pgif later:  pktfd restore"
    fi

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
# finds it. Reads state written at bind time. (Mellanox runs never bind, so
# there's nothing to restore.)
function _pktfd_restore() {
    local state=/tmp/pktfd-bound
    if [ ! -f "$state" ]; then
        echo "pktfd restore: no saved state ($state) — nothing was bound to vfio-pci."
        return 1
    fi

    local pci drv pgif fdif pgip k v
    while IFS='=' read -r k v; do
        case "$k" in
            pci)  pci=$v  ;; drv)  drv=$v  ;;
            pgif) pgif=$v ;; fdif) fdif=$v ;; pgip) pgip=$v ;;
            name) [ -z "$pgif" ] && pgif=$v ;;  # compat: old state used 'name'
        esac
    done < "$state"
    if [ -z "$pci" ]; then
        echo "pktfd restore: state file is malformed; remove $state and re-run setup."
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
        echo "pktfd restore: device rebound but no netdev appeared for $pci."
        echo "  Check 'ip link'; you may need to re-run, or driver '$drv' failed to attach."
        return 1
    fi
    pgif=${pgif:-$newname}
    if [ "$newname" != "$pgif" ]; then
        echo "Renaming '$newname' -> '$pgif'..."
        sudo ip link set "$newname" down && \
        sudo ip link set "$newname" name "$pgif"
    fi
    sudo ip link set "$pgif" up

    if [ -n "$pgip" ] && ! ip -4 -o addr show dev "$pgif" | grep -q "${pgip%%/*}"; then
        echo "Re-adding $pgip to $pgif (lost when the netdev was destroyed)..."
        sudo ip addr add "$pgip" dev "$pgif"
    fi
    if [ -n "$fdif" ] && ip link show "$fdif" >/dev/null 2>&1; then
        echo "Bouncing $fdif to re-establish carrier on the loopback link..."
        sudo ip link set "$fdif" down && sudo ip link set "$fdif" up
    fi

    rm -f "$state"
    echo "Done — $pgif is back on the kernel driver; ${fdif:+$fdif/}$pgif link restored."
}
