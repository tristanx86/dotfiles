# ── Firedancer Packet Generation ─────────────────────
# `pktfd` runs the current binary's pktgen; `pktfd setup` prepares an mlx5
# physical-loopback test rig. Relies on _fdbin/_fdconfig from firedancer.zsh
# and firedancer-config.zsh.

# DPDK's "main" lcore runs control/CLI and generates no traffic; pktgen also
# needs one core to service RX. Every remaining core is a dedicated TX
# (generation) core, and TX throughput scales with their count. Cores are
# allotted top-down so it fits a 16-core box (cores 0-15):
#   main 15 | RX 14 | TX 13, 12, 11, ...
# DPDK would otherwise default the main lcore to the lowest core in -l (a TX
# core here), so we pin it explicitly with --main-lcore.

function pktfd() {
    if [ "$1" = setup ]; then shift; _pktfd_setup "$@"; return; fi
    sudo "$(_fdbin)" pktgen --config "$(_fdconfig)"
}

# pktfd setup: point mel0 at the firedancer peer (route + static ARP), then
# optionally launch DPDK pktgen on mel1 aimed back at mel0. Designed for mlx5
# loopback testing: name the firedancer NIC 'mel0' and the pktgen NIC 'mel1'.
function _pktfd_setup() {
    if ! ip link show mel0 >/dev/null 2>&1; then
        echo "pktfd setup: interface 'mel0' not found."
        echo "  Name the NIC used for running firedancer 'mel0', and give it a /30:"
        echo "    sudo ip addr add 169.254.1.1/30 dev mel0"
        return 1
    fi

    echo "Configuring mel0 route + static neighbor for the firedancer peer..."
    sudo ip r replace 10.181.80.14 dev mel0
    sudo ip n replace 10.181.80.14 lladdr aa:aa:aa:aa:aa:aa dev mel0

    local ans
    read "ans?Also start DPDK pktgen on mel1? [y/N] "
    case "$ans" in
        y|Y|yes|Yes) ;;
        *) echo "Done — firedancer mel0 setup only."; return 0 ;;
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

    if ! ip link show mel1 >/dev/null 2>&1; then
        echo "pktfd setup: interface 'mel1' not found."
        echo "  This setup is designed for mlx5 testing — name one NIC 'mel1' to use for DPDK pktgen."
        return 1
    fi
    if ! command -v pktgen >/dev/null 2>&1; then
        echo "pktfd setup: WARNING — DPDK/pktgen does not appear to be installed."
        echo "  Unless you know what you are doing, do not use this provided DPDK pktgen setup."
        return 1
    fi

    # Aim pktgen at mel0: its MAC and its 169.x IPv4 (the /30 link to mel1).
    local dstmac dstip pci cmds
    dstmac=$(cat /sys/class/net/mel0/address)
    dstip=$(ip -4 -o addr show dev mel0 | awk '{print $4}' | grep '^169\.' | head -1 | cut -d/ -f1)
    if [ -z "$dstip" ]; then
        echo "pktfd setup: mel0 has no 169.x IPv4. Set one, e.g.: sudo ip addr add 169.254.1.1/30 dev mel0"
        return 1
    fi
    pci=$(basename "$(readlink -f /sys/class/net/mel1/device)")   # e.g. 0000:01:00.1

    # Warn if any pktgen core isn't on mel1's NUMA node (cross-socket DMA skews results).
    local nicnode c cnode badcores n
    nicnode=$(cat /sys/class/net/mel1/device/numa_node 2>/dev/null)
    if [ -n "$nicnode" ] && [ "$nicnode" != "-1" ]; then
        for c in {$txlo..$main}; do
            cnode=""
            for n in /sys/devices/system/cpu/cpu$c/node*(N); do cnode=${n##*/node}; done
            [ -n "$cnode" ] && [ "$cnode" != "$nicnode" ] && badcores="${badcores} $c"
        done
        if [ -n "$badcores" ]; then
            echo "pktfd setup: WARNING — mel1 is on NUMA node $nicnode but core(s)$badcores are on another node."
            echo "  Cross-socket DMA will skew results; pin to cores on node $nicnode for accurate numbers."
        fi
    fi

    echo "DPDK pktgen core plan on mel1:"
    echo "  $main    main lcore (DPDK control/CLI — no traffic)"
    echo "  $rxcore    RX core"
    echo "  $txrange  TX core(s) x$ntx  ->  ~${est} Mpps max (rough 30 Mpps/core guide, capped by NIC line rate)"

    # Hugepages: DPDK/pktgen needs 2MB hugepages *and* a mounted hugetlbfs to
    # back them — reserving nr_hugepages alone gives "no mounted hugetlbfs found
    # for that size". Reserve a generous count that scales with TX cores (on the
    # NIC's NUMA node when known), then mount hugetlbfs if the kernel hasn't.
    local npages=$(( 2048 + (ntx - 1) * 512 ))   # ~4 GiB + 1 GiB per extra TX core
    local hp_path=/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
    local hp_node="/sys/devices/system/node/node${nicnode}/hugepages/hugepages-2048kB/nr_hugepages"
    [ -n "$nicnode" ] && [ "$nicnode" != "-1" ] && [ -e "$hp_node" ] && hp_path="$hp_node"

    echo "Reserving $npages x 2MB hugepages ($((npages * 2)) MiB) via $hp_path..."
    echo "$npages" | sudo tee "$hp_path" >/dev/null
    local got; got=$(cat "$hp_path" 2>/dev/null)
    if [ -n "$got" ] && [ "$got" -lt "$npages" ]; then
        echo "pktfd setup: WARNING — kernel reserved only $got/$npages hugepages (likely memory fragmentation)."
        echo "  Free memory or reboot if pktgen reports insufficient hugepage memory."
    fi

    # EAL matches hugetlbfs mounts to pages *by page size*. A pre-existing
    # /dev/hugepages is often a 1GB mount (default_hugepagesz=1G), which is why
    # reserving 2MB pages still yields "no mounted hugetlbfs found for that
    # size". So mount our own dedicated 2MB hugetlbfs rather than assuming
    # /dev/hugepages is 2MB. (EAL scans all mounts, so any 2MB mount works.)
    local hugemnt=/mnt/huge-2m
    if ! grep -q " $hugemnt hugetlbfs " /proc/mounts; then
        echo "Mounting 2MB hugetlbfs at $hugemnt..."
        sudo mkdir -p "$hugemnt"
        sudo mount -t hugetlbfs -o pagesize=2M nodev "$hugemnt"
    fi
    if ! grep -q " $hugemnt hugetlbfs " /proc/mounts; then
        echo "pktfd setup: WARNING — failed to mount a 2MB hugetlbfs at $hugemnt; pktgen will likely abort."
    fi

    # pktgen runtime commands (loaded via -f): UDP 64B from the .2 peer -> mel0:9000.
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

    echo "Launching pktgen on mel1 ($pci) -> mel0 ($dstip / $dstmac), lcores $lcores (main $main)..."
    sudo pktgen -l "$lcores" -n 4 -a "$pci" --main-lcore "$main" --huge-dir "$hugemnt" -- -m "$map" -f "$cmds"
}
