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
#
# `floodfd dpdk` reuses pktfd's DPDK/NIC helpers (_fd_pick_iface,
# _fd_is_mellanox, _fd_lcore_plan, _fd_check_numa, _fd_reserve_hugepages,
# _fd_vfio_bind/_fd_vfio_restore) from firedancer-pktgen.zsh — same DPDK
# pktgen mechanics as pktfd, aimed at an over-the-wire target instead of a
# physical-loopback rig.

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

# floodfd setup: pick the sending NIC, take a destination IP, then ping it
# and read the resolved MAC out of the neighbor table. The ping doubles as a
# reachability check — if it fails, something's wrong with routing/cabling
# before you ever get to flooding.
function _floodfd_setup() {
    local iface
    iface=$(_fd_pick_iface "floodfd" "Sending NIC" "$(_floodfd_get if)") || return 1

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

# _floodfd_ensure_dpdk: install DPDK + build Pktgen-DPDK from source if the
# 'pktgen' binary isn't on PATH. DPDK's dev packages are in standard distro
# repos, but Pktgen-DPDK itself normally isn't, so it's built from source
# into ~/.local/src (no root needed for the clone/build, only the final
# 'ninja install').
PKTGEN_SRC_DIR="$HOME/.local/src/pktgen-dpdk"
function _floodfd_ensure_dpdk() {
    command -v pktgen >/dev/null 2>&1 && return 0

    echo "floodfd dpdk: 'pktgen' not found on PATH."
    echo "  This installs DPDK's dev packages via the system package manager,"
    echo "  then clones + builds Pktgen-DPDK from source into $PKTGEN_SRC_DIR."
    local ans
    read "ans?Proceed? [y/N] "
    case "$ans" in
        y|Y|yes|Yes) ;;
        *) echo "Aborted — install pktgen manually, or re-run to retry."; return 1 ;;
    esac

    local pkgmgr
    if command -v apt-get >/dev/null 2>&1; then
        pkgmgr=apt
    elif command -v dnf >/dev/null 2>&1; then
        pkgmgr=dnf
    elif command -v yum >/dev/null 2>&1; then
        pkgmgr=yum
    else
        echo "floodfd dpdk: no supported package manager found (apt-get/dnf/yum) — install DPDK + Pktgen-DPDK manually."
        return 1
    fi

    echo "Installing DPDK + build dependencies ($pkgmgr)..."
    case "$pkgmgr" in
        apt)
            sudo apt-get update -y
            sudo apt-get install -y dpdk dpdk-dev meson ninja-build pkg-config libnuma-dev git \
                || { echo "floodfd dpdk: package install failed — install DPDK manually and re-run."; return 1; }
            ;;
        dnf|yum)
            sudo "$pkgmgr" install -y dpdk dpdk-devel meson ninja-build pkgconf-pkg-config numactl-devel git \
                || { echo "floodfd dpdk: package install failed — install DPDK manually and re-run."; return 1; }
            ;;
    esac

    mkdir -p "$(dirname "$PKTGEN_SRC_DIR")"
    if [ -d "$PKTGEN_SRC_DIR/.git" ]; then
        echo "Updating existing Pktgen-DPDK checkout..."
        git -C "$PKTGEN_SRC_DIR" pull || return 1
    else
        echo "Cloning Pktgen-DPDK..."
        git clone https://github.com/pktgen/Pktgen-DPDK.git "$PKTGEN_SRC_DIR" || return 1
    fi

    echo "Building Pktgen-DPDK (meson + ninja)..."
    (
        cd "$PKTGEN_SRC_DIR" || exit 1
        rm -rf build
        meson setup build || exit 1
        ninja -C build || exit 1
        sudo ninja -C build install || exit 1
    ) || { echo "floodfd dpdk: build failed — see output above."; return 1; }
    sudo ldconfig

    if ! command -v pktgen >/dev/null 2>&1; then
        echo "floodfd dpdk: built successfully but 'pktgen' still not on PATH — check /usr/local/bin is in PATH."
        return 1
    fi
    echo "pktgen installed: $(command -v pktgen)"
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

    local plan main rxcore txlo txrange lcores map est
    plan=$(_fd_lcore_plan "floodfd dpdk" "$ntx") || return 1
    read -r main rxcore txlo txrange lcores map est <<< "$plan"

    _floodfd_ensure_dpdk || return 1
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
    _fd_is_mellanox "$iface" "$curdrv" && mellanox=1

    _fd_check_numa "floodfd dpdk" "$iface" "$nicnode" "$txlo" "$main"

    echo "DPDK pktgen core plan on $iface:"
    echo "  $main    main lcore (DPDK control/CLI — no traffic)"
    echo "  $rxcore    RX core"
    echo "  $txrange  TX core(s) x$ntx  ->  ~${est} Mpps max (rough 30 Mpps/core guide, capped by NIC line rate)"

    _fd_reserve_hugepages "$ntx"

    [ "$mellanox" != 1 ] && _fd_vfio_bind floodfd "$iface" "$pci" "$curdrv" /tmp/floodfd-bound "" "$ifip"

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
# to its kernel driver and rename the reborn netdev back to its original name.
function _floodfd_restore() { _fd_vfio_restore "floodfd restore" /tmp/floodfd-bound; }
