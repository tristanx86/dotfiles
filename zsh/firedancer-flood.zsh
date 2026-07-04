# ── Flood Load Generation ─────────────────────────────
# `floodfd` load-tests a remote firedancer validator from a *separate* box:
# same idea as pktfd's DPDK pktgen, but aimed at a target over the wire
# instead of a physical-loopback rig. Two engines, chosen explicitly each
# run — floodfd is standalone (no _fdbin/_fdconfig dependency):
#   floodfd dpdk    DPDK pktgen (userspace, needs a NIC bound to vfio-pci/mlx5)
#   floodfd kernel  in-kernel pktgen module (no DPDK/hugepages needed)
# Both always send 64B (min-sized) UDP packets at dport 9000, matching pktfd.
#
# `floodfd setup` resolves and saves the target once: pick the sending NIC,
# enter the destination IP, then floodfd pings it and reads the resolved MAC
# out of the neighbor table — which doubles as a reachability check before
# you start flooding. Picks are saved per-machine (untracked); Enter keeps
# the last value at every subsequent prompt.

FLOODFD_STATE_FILE="$HOME/.config/dotfiles/floodfd-state"
_floodfd_get() { grep "^$1=" "$FLOODFD_STATE_FILE" 2>/dev/null | cut -d= -f2-; }
_floodfd_set() {
    local key=$1 val=$2
    mkdir -p "$(dirname "$FLOODFD_STATE_FILE")"
    local tmp="${FLOODFD_STATE_FILE}.tmp"
    { [ -f "$FLOODFD_STATE_FILE" ] && grep -v "^$key=" "$FLOODFD_STATE_FILE"; printf '%s=%s\n' "$key" "$val"; } > "$tmp"
    mv "$tmp" "$FLOODFD_STATE_FILE"
}

function floodfd() {
    case "$1" in
        setup)   shift; _floodfd_setup "$@";   return ;;
        dpdk)    shift; _floodfd_dpdk "$@";    return ;;
        kernel)  shift; _floodfd_kernel "$@";  return ;;
        stop)    shift; _floodfd_stop "$@";    return ;;
        restore) shift; _floodfd_restore "$@"; return ;;
        *)
            echo "Usage: floodfd setup | dpdk | kernel | stop | restore"
            return 1
            ;;
    esac
}

# _floodfd_pick <label> [current]: list network interfaces and prompt for
# one, printing the choice to stdout. Enter keeps [current] if given.
function _floodfd_pick() {
    local label=$1 cur=$2
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
    [ ${#ifaces} -eq 0 ] && { echo "floodfd: no network interfaces found." >&2; return 1; }

    local sel
    read "sel?${label}${cur:+ (Enter = keep '$cur')} [1-${#ifaces}]: "
    if [ -z "$sel" ]; then
        [ -z "$cur" ] && { echo "floodfd: no interface selected." >&2; return 1; }
        echo "$cur"
        return 0
    fi
    if ! [[ "$sel" =~ '^[0-9]+$' ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#ifaces} ]; then
        echo "floodfd: invalid selection '$sel'." >&2
        return 1
    fi
    echo "${ifaces[$sel]}"
}

# floodfd setup: pick the sending NIC, take a destination IP, then ping it
# and read the resolved MAC out of the neighbor table. The ping doubles as a
# reachability check — if it fails, something's wrong with routing/cabling
# before you ever get to flooding.
function _floodfd_setup() {
    local iface
    iface=$(_floodfd_pick "Sending NIC" "$(_floodfd_get if)") || return 1

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "floodfd setup: interface '$iface' not found."
        return 1
    fi

    if ! ip -4 -o addr show dev "$iface" | grep -q .; then
        local cidr
        read "cidr?$iface has no IPv4 (needed to ping/ARP the target). Assign one (e.g. 10.0.0.2/24): "
        [ -z "$cidr" ] && { echo "floodfd setup: no address given, aborting."; return 1; }
        sudo ip addr add "$cidr" dev "$iface" || return 1
    fi

    local curdestip destip
    curdestip=$(_floodfd_get destip)
    read "destip?Destination IP (the validator under test)${curdestip:+ (Enter = keep '$curdestip')}: "
    destip=${destip:-$curdestip}
    [ -z "$destip" ] && { echo "floodfd setup: no destination IP given."; return 1; }

    echo "Pinging $destip via $iface to resolve its MAC (also confirms reachability)..."
    if ! ping -c2 -W2 -I "$iface" "$destip" >/dev/null 2>&1; then
        echo "floodfd setup: $destip is not reachable from $iface — check routing/cabling before flooding."
        return 1
    fi

    local destmac
    destmac=$(ip neigh show "$destip" dev "$iface" 2>/dev/null | awk '/lladdr/{for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1)}' | head -1)
    if [ -z "$destmac" ]; then
        echo "floodfd setup: ping succeeded but no ARP entry resolved for $destip on $iface."
        return 1
    fi

    _floodfd_set if "$iface"
    _floodfd_set destip "$destip"
    _floodfd_set destmac "$destmac"
    echo "Target confirmed: $destip ($destmac) reachable via $iface."
}

# floodfd kernel: in-kernel pktgen flood at a target Mpps. pktgen's kernel
# threads (kpktgend_N) are pinned 1:1 to CPU N, so "core selection" here just
# means which kpktgend_N thread a device gets loaded into — cores are picked
# top-down (highest first) to match pktfd's convention and avoid low cores
# other tools tend to pin to.
function _floodfd_kernel() {
    local iface destip destmac
    iface=$(_floodfd_get if); destip=$(_floodfd_get destip); destmac=$(_floodfd_get destmac)
    if [ -z "$iface" ] || [ -z "$destip" ] || [ -z "$destmac" ]; then
        echo "floodfd kernel: no target configured — run 'floodfd setup' first."
        return 1
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "floodfd kernel: interface '$iface' not found (was it rebound to vfio-pci? check 'floodfd restore')."
        return 1
    fi

    local curcores ncores
    curcores=$(_floodfd_get kerncores); curcores=${curcores:-4}
    read "ncores?TX cores/threads? [${curcores}] "
    ncores=${ncores:-$curcores}
    if ! [[ "$ncores" =~ '^[0-9]+$' ]] || [ "$ncores" -lt 1 ]; then
        echo "floodfd kernel: invalid core count '$ncores'."
        return 1
    fi
    _floodfd_set kerncores "$ncores"

    local hi=$(( $(nproc) - 1 )) lo
    lo=$((hi - ncores + 1))
    if [ "$lo" -lt 0 ]; then
        echo "floodfd kernel: $ncores cores would run past core 0 (highest core = $hi). Choose fewer."
        return 1
    fi

    local currate rate
    currate=$(_floodfd_get kernrate); currate=${currate:-MAX}
    read "rate?Target Mpps (or MAX)? [${currate}] "
    rate=${rate:-$currate}
    _floodfd_set kernrate "$rate"

    local delay_ns
    if [ "$rate" = MAX ] || [ "$rate" = max ]; then
        delay_ns=0
        echo "Configuring $ncores threads (cores $lo-$hi) for MAXIMUM speed..."
    else
        delay_ns=$(awk -v mpps="$rate" -v cores="$ncores" 'BEGIN {
            total_pps = mpps * 1000000;
            pps_per_core = total_pps / cores;
            printf "%d", 1000000000 / pps_per_core
        }')
        echo "Configuring $ncores threads (cores $lo-$hi) for target $rate Mpps (delay ${delay_ns}ns/core)..."
    fi

    sudo modprobe pktgen
    echo "stop" | sudo tee /proc/net/pktgen/pgctrl >/dev/null 2>&1

    local i core dev thread
    for ((i = 0; i < ncores; i++)); do
        core=$((hi - i))
        thread="kpktgend_${core}"
        dev="${iface}@${i}"

        echo "rem_device_all" | sudo tee "/proc/net/pktgen/$thread" >/dev/null
        echo "add_device $dev" | sudo tee "/proc/net/pktgen/$thread" >/dev/null

        echo "count 0"          | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "clone_skb 10000"  | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "pkt_size 64"      | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "delay $delay_ns"  | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "queue_map_min $i" | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "queue_map_max $i" | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "dst $destip"      | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "dst_mac $destmac" | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "udp_dst_min 9000" | sudo tee "/proc/net/pktgen/$dev" >/dev/null
        echo "udp_dst_max 9000" | sudo tee "/proc/net/pktgen/$dev" >/dev/null
    done

    # Writing "start" blocks until "stop" is written, so background it and
    # run the Mpps monitor in the foreground.
    echo "start" | sudo tee /proc/net/pktgen/pgctrl >/dev/null &

    echo "Flooding $destip ($destmac) via $iface — cores $lo-$hi, target ${rate} Mpps."
    echo "Ctrl-C stops watching (traffic keeps flowing — run 'floodfd stop' to actually stop it)."
    echo "------------------------------------------------------"

    local p1 p2 diff mpps val
    while true; do
        p1=0
        for ((i = 0; i < ncores; i++)); do
            val=$(grep "pkts-sofar" "/proc/net/pktgen/${iface}@${i}" 2>/dev/null | awk '{print $2}')
            p1=$((p1 + val))
        done

        sleep 1

        p2=0
        for ((i = 0; i < ncores; i++)); do
            val=$(grep "pkts-sofar" "/proc/net/pktgen/${iface}@${i}" 2>/dev/null | awk '{print $2}')
            p2=$((p2 + val))
        done

        diff=$((p2 - p1))
        mpps=$(awk -v diff="$diff" 'BEGIN { printf "%.2f", diff / 1000000 }')
        echo "Current TX speed: $mpps Mpps"
    done
}

# floodfd stop: halt the in-kernel pktgen flood (devices stay configured).
function _floodfd_stop() {
    echo "stop" | sudo tee /proc/net/pktgen/pgctrl >/dev/null 2>&1
    echo "Kernel pktgen stopped."
}

# floodfd dpdk: bind the flood NIC to vfio-pci (skipped for Mellanox) and
# launch DPDK pktgen aimed at the saved target. Same core-layout convention
# as pktfd: main lcore highest, then RX, then TX cores going down — DPDK's
# main lcore runs control/CLI (no traffic) and pktgen dedicates one core to
# RX; every other core is TX (generation), and TX throughput scales with
# their count. Leaves you at pktgen's interactive prompt — 'start 0' and
# rate-limiting ('set 0 rate <pct>') are yours to run by hand.
function _floodfd_dpdk() {
    local iface destip destmac
    iface=$(_floodfd_get if); destip=$(_floodfd_get destip); destmac=$(_floodfd_get destmac)
    if [ -z "$iface" ] || [ -z "$destip" ] || [ -z "$destmac" ]; then
        echo "floodfd dpdk: no target configured — run 'floodfd setup' first."
        return 1
    fi

    local curcores ntx
    curcores=$(_floodfd_get dpdkcores); curcores=${curcores:-1}
    echo "DPDK uses 1 lcore for control + 1 for RX; each extra TX core adds ~30 Mpps (64B)."
    read "ntx?How many TX (generation) cores? [${curcores}] "
    ntx=${ntx:-$curcores}
    if ! [[ "$ntx" =~ '^[0-9]+$' ]] || [ "$ntx" -lt 1 ]; then
        echo "floodfd dpdk: invalid TX core count '$ntx'."
        return 1
    fi
    _floodfd_set dpdkcores "$ntx"

    local main=15 rxcore=14 txhi=13
    local txlo=$((txhi - ntx + 1))
    local lcores="${txlo}-${main}"
    local txrange="$txhi"
    [ "$txlo" -lt "$txhi" ] && txrange="${txlo}-${txhi}"
    local map="[${rxcore}:${txrange}].0"
    local est=$((ntx * 30))

    if [ ! -d "/sys/devices/system/cpu/cpu$main" ]; then
        echo "floodfd dpdk: layout needs at least 16 cores (uses up to core $main); machine has $(nproc)."
        return 1
    fi
    if [ "$txlo" -lt 0 ]; then
        echo "floodfd dpdk: $ntx TX cores would run past core 0 (lowest = $txlo). Choose fewer."
        return 1
    fi

    if ! command -v pktgen >/dev/null 2>&1; then
        echo "floodfd dpdk: WARNING — DPDK/pktgen does not appear to be installed."
        return 1
    fi
    if [ ! -e "/sys/class/net/$iface" ]; then
        echo "floodfd dpdk: no netdev for '$iface' — already bound to vfio-pci from a previous run? Check 'floodfd restore'."
        return 1
    fi

    local pci nicnode curdrv ifip
    pci=$(basename "$(readlink -f /sys/class/net/$iface/device)")
    nicnode=$(cat /sys/class/net/$iface/device/numa_node 2>/dev/null)
    curdrv=$(basename "$(readlink -f /sys/class/net/$iface/device/driver)" 2>/dev/null)
    ifip=$(ip -4 -o addr show dev "$iface" | awk '{print $4}' | head -1)

    local mellanox=0
    case "$curdrv" in mlx5_core|mlx5) mellanox=1 ;; esac
    local defans; [ "$mellanox" = 1 ] && defans=Y || defans=N
    [ -n "$curdrv" ] && echo "Detected kernel driver for $iface: $curdrv"
    local ans
    read "ans?Mellanox/mlx5 NIC (no vfio-pci rebind needed)? [$defans]: "
    ans=${ans:-$defans}
    case "$ans" in y|Y|yes|Yes) mellanox=1 ;; *) mellanox=0 ;; esac

    # Warn if any TX/RX/main core isn't on the NIC's NUMA node (cross-socket DMA skews results).
    local c cnode badcores n
    if [ -n "$nicnode" ] && [ "$nicnode" != "-1" ]; then
        for c in {$txlo..$main}; do
            cnode=""
            for n in /sys/devices/system/cpu/cpu$c/node*(N); do cnode=${n##*/node}; done
            [ -n "$cnode" ] && [ "$cnode" != "$nicnode" ] && badcores="${badcores} $c"
        done
        if [ -n "$badcores" ]; then
            echo "floodfd dpdk: WARNING — $iface is on NUMA node $nicnode but core(s)$badcores are on another node."
            echo "  Cross-socket DMA will skew results; pin to cores on node $nicnode for accurate numbers."
        fi
    fi

    echo "DPDK pktgen core plan on $iface:"
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
        printf 'pci=%s\ndrv=%s\nif=%s\nifip=%s\n' \
            "$pci" "$curdrv" "$iface" "$ifip" > /tmp/floodfd-bound
        echo "  To rebind the kernel driver + restore $iface later:  floodfd restore"
    fi

    local cmds=/tmp/floodfd-dpdk.pkt
    cat > "$cmds" <<EOF
set 0 dst mac $destmac
set 0 dst ip $destip
set 0 proto udp
set 0 dport 9000
set 0 size 64
disable 0 vlan
set 0 src ip ${ifip:-0.0.0.0}
EOF

    echo "Launching pktgen on $iface ($pci) -> $destip ($destmac), lcores $lcores (main $main)..."
    echo "(pktgen drops you at its interactive prompt — run 'start 0' yourself when ready.)"
    sudo pktgen -l "$lcores" -n 4 -a "$pci" --main-lcore "$main" -- -m "$map" -f "$cmds"
}

# floodfd restore: undo a vfio-pci bind from `floodfd dpdk` — rebind the NIC
# to its kernel driver and rename the reborn netdev back to its original
# name, mirroring pktfd restore.
function _floodfd_restore() {
    local state=/tmp/floodfd-bound
    if [ ! -f "$state" ]; then
        echo "floodfd restore: no saved state ($state) — nothing was bound to vfio-pci."
        return 1
    fi

    local pci drv iface ifip k v
    while IFS='=' read -r k v; do
        case "$k" in
            pci)  pci=$v  ;; drv)  drv=$v  ;;
            if)   iface=$v ;; ifip) ifip=$v ;;
        esac
    done < "$state"
    if [ -z "$pci" ]; then
        echo "floodfd restore: state file is malformed; remove $state and re-run 'floodfd dpdk'."
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
        echo "floodfd restore: device rebound but no netdev appeared for $pci."
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

    if [ -n "$ifip" ] && ! ip -4 -o addr show dev "$iface" | grep -q "${ifip%%/*}"; then
        echo "Re-adding $ifip to $iface (lost when the netdev was destroyed)..."
        sudo ip addr add "$ifip" dev "$iface"
    fi

    rm -f "$state"
    echo "Done — $iface is back on the kernel driver."
}
