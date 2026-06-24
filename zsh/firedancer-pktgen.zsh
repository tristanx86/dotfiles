# ── Firedancer Packet Generation ─────────────────────
# `pktfd` runs the current binary's pktgen; `pktfd setup` prepares a physical-
# loopback test rig. Relies on _fdbin/_fdconfig from firedancer.zsh and
# firedancer-config.zsh.

# DPDK's "main" lcore runs control/CLI and generates no traffic; pktgen also
# needs one core to service RX. Every remaining core is a dedicated TX
# (generation) core, and TX throughput scales with their count. Cores are
# allotted top-down so it fits a 16-core box (cores 0-15):
#   main 15 | RX 14 | TX 13, 12, 11, ...
# DPDK would otherwise default the main lcore to the lowest core in -l (a TX
# core here), so we pin it explicitly with --main-lcore.

function pktfd() {
    if [ "$1" = setup ]; then shift; _pktfd_setup "$@"; return; fi
    if [ "$1" = restore ]; then shift; _pktfd_restore "$@"; return; fi
    sudo "$(_fdbin)" pktgen --config "$(_fdconfig)"
}

# Ensure an interface named <target> exists; if not, offer to rename an existing
# one (picked from a numbered list) to it. <role> is shown in the prompts so the
# user knows which NIC they're choosing; <exclude> drops one name from the list
# (so the fdi1 prompt can't clobber fdi0). If <ip> is given and <target> has no
# IPv4, offer to assign it. Renaming needs the link down first.
# Returns 0 if <target> exists afterwards, 1 otherwise.
function _pktfd_ensure_iface() {
    local target=$1 role=$2 exclude=$3 ip=$4 ans

    if ! ip link show "$target" >/dev/null 2>&1; then
        echo "pktfd setup: interface '$target' not found (the $role NIC)."
        read "ans?Rename an existing interface to '$target'? [y/N] "
        case "$ans" in
            y|Y|yes|Yes) ;;
            *) return 1 ;;
        esac

        echo "Available interfaces:"
        local ifaces=() i idx=1
        for i in /sys/class/net/*(N); do
            i=${i##*/}
            [ "$i" = lo ] && continue
            [ -n "$exclude" ] && [ "$i" = "$exclude" ] && continue
            ifaces+=("$i")
            printf "  %d) %s\n" "$idx" "$i"
            idx=$((idx + 1))
        done
        if [ ${#ifaces} -eq 0 ]; then
            echo "pktfd setup: no interfaces available to rename."
            return 1
        fi

        local sel
        read "sel?Select the $role interface (will be renamed to '$target') [1-${#ifaces}]: "
        if ! [[ "$sel" =~ '^[0-9]+$' ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#ifaces} ]; then
            echo "pktfd setup: invalid selection '$sel'."
            return 1
        fi
        local old=${ifaces[$sel]}
        if [ "$old" != "$target" ]; then
            echo "Renaming '$old' -> '$target'..."
            if ! { sudo ip link set "$old" down && \
                   sudo ip link set "$old" name "$target" && \
                   sudo ip link set "$target" up; }; then
                echo "pktfd setup: failed to rename '$old' to '$target'."
                return 1
            fi
            echo "  '$old' is now '$target'."
        fi
    fi

    # Offer the /30 link address if requested and the link has no IPv4 yet.
    if [ -n "$ip" ] && ! ip -4 -o addr show dev "$target" | grep -q .; then
        read "ans?Assign $ip to '$target'? [Y/n] "
        case "$ans" in
            n|N|no|No) ;;
            *) sudo ip addr add "$ip" dev "$target" && echo "  assigned $ip to $target" ;;
        esac
    fi
    return 0
}

# pktfd setup: point fdi0 at the firedancer peer (route + static ARP), then
# optionally launch DPDK pktgen on fdi1 aimed back at fdi0. Works with any
# DPDK-supported NIC — Mellanox (mlx5, bifurcated) needs no rebind, while Intel
# (i40e/ixgbe/ice) and others are bound to vfio-pci for pktgen. Name the
# firedancer NIC 'fdi0' and the pktgen NIC 'fdi1'.
function _pktfd_setup() {
    if ! _pktfd_ensure_iface fdi0 firedancer "" 169.254.1.1/30; then
        echo "  Name the NIC used for running firedancer 'fdi0', and give it a /30:"
        echo "    sudo ip addr add 169.254.1.1/30 dev fdi0"
        return 1
    fi

    echo "Configuring fdi0 route + static neighbor for the firedancer peer..."
    sudo ip r replace 10.181.80.14 dev fdi0
    sudo ip n replace 10.181.80.14 lladdr aa:aa:aa:aa:aa:aa dev fdi0

    local ans
    read "ans?Also start DPDK pktgen on fdi1? [y/N] "
    case "$ans" in
        y|Y|yes|Yes) ;;
        *) echo "Done — firedancer fdi0 setup only."; return 0 ;;
    esac

    # How many TX (generation) cores? More cores -> more Mpps, up to NIC line rate.
    local ntx
    echo "DPDK uses 1 lcore for control + 1 for RX; each extra TX core adds ~30 Mpps (64B)."
    read "ntx?How many TX (generation) cores? [1] "
    ntx=${ntx:-1}
    if ! [[ "$ntx" =~ '^[0-9]+$' ]] || [ "$ntx" -lt 1 ]; then
        echo "pktfd setup: invalid TX core count '$ntx' (need a positive integer)."
        return 1
    fi

    # Lay out lcores top-down (fits a 16-core box):  main 15 | RX 14 | TX 13,12,...
    local main=15
    local rxcore=14
    local txhi=13                      # first (highest-numbered) TX core
    local txlo=$((txhi - ntx + 1))     # lowest TX core after adding ntx of them
    local lcores="${txlo}-${main}"     # contiguous block txlo..15
    local txrange="$txhi"
    [ "$txlo" -lt "$txhi" ] && txrange="${txlo}-${txhi}"
    local map="[${rxcore}:${txrange}].0"
    local est=$((ntx * 30))   # 30 Mpps/core is a rough 64B guide for the max case, not a guarantee

    if [ ! -d "/sys/devices/system/cpu/cpu$main" ]; then
        echo "pktfd setup: this layout needs at least 16 cores (uses up to core $main); machine has $(nproc)."
        return 1
    fi
    if [ "$txlo" -lt 0 ]; then
        echo "pktfd setup: $ntx TX cores would run past core 0 (lowest would be $txlo). Choose fewer TX cores."
        return 1
    fi

    if ! _pktfd_ensure_iface fdi1 "DPDK pktgen" fdi0 169.254.1.2/30; then
        echo "  Name one NIC 'fdi1' to use for DPDK pktgen."
        return 1
    fi
    if ! command -v pktgen >/dev/null 2>&1; then
        echo "pktfd setup: WARNING — DPDK/pktgen does not appear to be installed."
        echo "  Unless you know what you are doing, do not use this provided DPDK pktgen setup."
        return 1
    fi

    # Capture fdi1's PCI address, NUMA node and kernel driver now — binding it to
    # vfio-pci (Intel etc.) removes the netdev, so /sys/class/net/fdi1 disappears.
    local pci nicnode curdrv
    pci=$(basename "$(readlink -f /sys/class/net/fdi1/device)")        # e.g. 0000:01:00.1
    nicnode=$(cat /sys/class/net/fdi1/device/numa_node 2>/dev/null)
    curdrv=$(basename "$(readlink -f /sys/class/net/fdi1/device/driver)" 2>/dev/null)

    # Which driver does the pktgen NIC use? Mellanox (mlx5) is a bifurcated PMD —
    # DPDK drives it while it stays on the kernel driver, so no rebind. Everything
    # else (Intel i40e/ixgbe/ice, ...) must be unbound and bound to vfio-pci.
    echo ""
    [ -n "$curdrv" ] && echo "fdi1 kernel driver detected: $curdrv"
    echo "Which driver does the pktgen NIC (fdi1) use?"
    echo "  1) mlx5  — Mellanox/NVIDIA (bifurcated; DPDK uses it in place, no rebind)"
    echo "  2) i40e  — Intel 700-series (X710/XL710)"
    echo "  3) ixgbe — Intel 82599 / X520 / X540"
    echo "  4) ice   — Intel 800-series (E810)"
    echo "  5) other — any other DPDK-supported NIC (bound to vfio-pci)"
    # Pre-select the list item matching the detected kernel driver (Mellanox's is
    # 'mlx5_core'); the user can just hit Enter to accept it.
    local drvsel mellanox=0 defsel=""
    case "$curdrv" in
        mlx5_core|mlx5) defsel=1 ;;
        i40e) defsel=2 ;;
        ixgbe) defsel=3 ;;
        ice) defsel=4 ;;
        ?*) defsel=5 ;;
    esac
    read "drvsel?Select [1-5]${defsel:+ [$defsel]}: "
    drvsel=${drvsel:-$defsel}
    case "$drvsel" in
        1) mellanox=1 ;;
        2|3|4|5) mellanox=0 ;;
        *) echo "pktfd setup: invalid selection '$drvsel'."; return 1 ;;
    esac

    # Aim pktgen at fdi0: its MAC and its 169.x IPv4 (the /30 link to fdi1).
    local dstmac dstip cmds
    dstmac=$(cat /sys/class/net/fdi0/address)
    dstip=$(ip -4 -o addr show dev fdi0 | awk '{print $4}' | grep '^169\.' | head -1 | cut -d/ -f1)
    if [ -z "$dstip" ]; then
        echo "pktfd setup: fdi0 has no 169.x IPv4. Set one, e.g.: sudo ip addr add 169.254.1.1/30 dev fdi0"
        return 1
    fi

    # Warn if any pktgen core isn't on fdi1's NUMA node (cross-socket DMA skews results).
    local c cnode badcores n
    if [ -n "$nicnode" ] && [ "$nicnode" != "-1" ]; then
        for c in {$txlo..$main}; do
            cnode=""
            for n in /sys/devices/system/cpu/cpu$c/node*(N); do cnode=${n##*/node}; done
            [ -n "$cnode" ] && [ "$cnode" != "$nicnode" ] && badcores="${badcores} $c"
        done
        if [ -n "$badcores" ]; then
            echo "pktfd setup: WARNING — fdi1 is on NUMA node $nicnode but core(s)$badcores are on another node."
            echo "  Cross-socket DMA will skew results; pin to cores on node $nicnode for accurate numbers."
        fi
    fi

    echo "DPDK pktgen core plan on fdi1:"
    echo "  $main    main lcore (DPDK control/CLI — no traffic)"
    echo "  $rxcore    RX core"
    echo "  $txrange  TX core(s) x$ntx  ->  ~${est} Mpps max (rough 30 Mpps/core guide, capped by NIC line rate)"

    # Reserve 2MB hugepages (1024 per TX core), and mount a 2MB hugetlbfs to back
    # them if one isn't already mounted — reserving alone gives EAL "no mounted
    # hugetlbfs found for that size" (e.g. when the system default is 1GB pages).
    local npages=$(( 1024 * ntx ))
    echo "Reserving $npages x 2MB hugepages ($((npages * 2)) MiB)..."
    echo "$npages" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null
    if ! grep -q 'hugetlbfs.*pagesize=2M' /proc/mounts; then
        sudo mkdir -p /mnt/huge && sudo mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge
    fi

    # Non-Mellanox NICs need their PCI device bound to vfio-pci before pktgen can
    # claim it. After this the fdi1 netdev is gone (DPDK owns the device).
    if [ "$mellanox" != 1 ]; then
        echo "Binding fdi1 ($pci, ${curdrv:-unknown}) to vfio-pci for DPDK..."
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
        # Record what we bound so `pktfd restore` can put it back on a re-run.
        printf 'pci=%s\ndrv=%s\nname=%s\n' "$pci" "$curdrv" fdi1 > /tmp/pktfd-bound
        echo "  To rebind the kernel driver + bring fdi1 back later:  pktfd restore"
    fi

    # pktgen runtime commands (loaded via -f): UDP 64B from the .2 peer -> fdi0:9000.
    cmds=/tmp/pktfd-setup.pkt
    cat > "$cmds" <<EOF
set 0 dst mac $dstmac
set 0 dst ip $dstip
set 0 proto udp
set 0 dport 9000
set 0 size 64
disable 0 vlan
set 0 src ip 169.254.1.2/30
EOF

    echo "Launching pktgen on fdi1 ($pci) -> fdi0 ($dstip / $dstmac), lcores $lcores (main $main)..."
    sudo pktgen -l "$lcores" -n 4 -a "$pci" --main-lcore "$main" -- -m "$map" -f "$cmds"
}

# pktfd restore: undo a vfio-pci bind from `pktfd setup` — rebind the pktgen NIC
# to its kernel driver and rename the reborn netdev back to fdi1, so the next
# `pktfd setup` finds it. Reads the state written at bind time. (Mellanox runs
# never bind, so there's nothing to restore.)
function _pktfd_restore() {
    local state=/tmp/pktfd-bound
    if [ ! -f "$state" ]; then
        echo "pktfd restore: no saved state ($state) — nothing was bound to vfio-pci."
        return 1
    fi

    local pci drv name k v
    while IFS='=' read -r k v; do
        case "$k" in pci) pci=$v ;; drv) drv=$v ;; name) name=$v ;; esac
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

    # The kernel re-creates the netdev under a fresh name; rename it back to fdi1.
    local newname n
    for n in /sys/bus/pci/devices/$pci/net/*(N); do newname=${n##*/}; done
    if [ -z "$newname" ]; then
        echo "pktfd restore: device rebound but no netdev appeared yet for $pci."
        echo "  Check 'ip link'; you may need to re-run, or the driver '$drv' failed to attach."
        return 1
    fi
    name=${name:-$newname}
    if [ "$newname" != "$name" ]; then
        echo "Renaming '$newname' -> '$name'..."
        sudo ip link set "$newname" down && \
        sudo ip link set "$newname" name "$name"
    fi
    sudo ip link set "$name" up

    # The vfio-pci bind destroyed the old netdev, so the reborn fdi1 has no IP.
    # Re-add the /30 link address, and bring fdi0 back up: while fdi1 was off the
    # kernel its cabled partner lost carrier and went NO-CARRIER (DOWN).
    if ! ip -4 -o addr show dev "$name" | grep -q '169\.'; then
        echo "Re-adding 169.254.1.2/30 to $name (lost when the netdev was destroyed)..."
        sudo ip addr add 169.254.1.2/30 dev "$name"
    fi
    if ip link show fdi0 >/dev/null 2>&1; then
        echo "Bouncing fdi0 to re-establish carrier on the loopback link..."
        sudo ip link set fdi0 down && sudo ip link set fdi0 up
    fi

    rm -f "$state"
    echo "Done — $name is back on the kernel driver; fdi0/$name link restored."
}
