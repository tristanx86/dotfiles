## Monitor

| Command | Action |
| :--- | :--- |
| `htop` / `btop` | Per-core meters, per-process core, CPU% sort. |
| `mpstat -P ALL 1` | Per-core utilisation incl. %irq / %soft / %idle. |
| `pidstat -t -p <pid> 1` | Per-thread CPU, ctx-switches, faults. |
| `vmstat 1` / `sar 1` | System-wide CPU, run queue, paging. |
| `watch -n1 'grep MHz /proc/cpuinfo'` | Live per-core frequency. |

## Topology & CPU

| Command | Action |
| :--- | :--- |
| `topo` | CPU topology + NUMA (cores, HT siblings, isolated). (alias) |
| `enable-ht` / `disable-ht` | Toggle hyperthreading. (alias) |
| `clockspeed <Ghz>` | Pin min/max CPU frequency. (alias) |

## Profiling (perf)

| Command | Action |
| :--- | :--- |
| `perf stat -e cache-misses,cache-references,cycles,instructions,branches,branch-misses <cmd>` | Cache misses, cycles, branches, IPC. |
| `perf top -C <cpu>` | Live hottest functions on a core. |
| `perf record -g -C <cpu> -- sleep 10` → `perf report` | Sampled call-graph profile. |
| `perf stat -d -d -d <cmd>` | IPC, frontend/backend stalls, cache levels. |

## Cache

Per-second (`-I 1000`) is best for live watching; **MPKI** (misses per 1k
instructions) and miss-% are the norm for comparing runs — perf prints the %
automatically when you pair loads with load-misses.

| Command | Action |
| :--- | :--- |
| `perf stat -I 1000 -p <pid> -e cycles,instructions,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses` | Per-second L1 + L3 accesses/misses with miss %. |
| `perf stat -M L1MPKI,L2MPKI,L3MPKI -p <pid>` | Misses per 1k instructions (names are CPU-specific — see `perf list metricgroup`). |
| `perf c2c record -p <pid>` → `perf c2c report` | Cache-line bouncing: hot lines + HITM (modified line stolen by another core) = true/false sharing. |
| `perf mem record -p <pid>` → `perf mem report` | Per-load latency and which cache level / NUMA node served it. |
| `perf list cache` | This CPU's exact L1/L2/L3 event names (L2 has no generic alias). |

## Tracing

| Command | Action |
| :--- | :--- |
| `bpftrace -e '...'` | Ad-hoc kernel/user probes (latency, counts, stacks). |
| `funclatency` / `argdist` (bcc) | Function latency histograms. |
| `hardirqs` / `softirqs` (bcc) | Time spent in IRQ handlers. |
| `trace-cmd record -p function_graph` | ftrace function-graph capture. |

## NIC (ethtool)

| Command | Action |
| :--- | :--- |
| `ethtool -S <if>` | NIC stats: rx/tx drops, errors, missed, overruns. |
| `ethtool <if>` | Link speed / duplex / status. |
| `ethtool -i <if>` | Driver, firmware, PCI bus info. |
| `ethtool -c <if>` | Interrupt coalescing (lower = less latency, more IRQs). |
| `ethtool -g <if>` | Ring buffer sizes (rx/tx). |
| `ethtool -k <if>` | Offloads (GRO/LRO/TSO — often off for latency). |
| `ethtool -l <if>` | Channel / queue counts. |
| `ethtool -T <if>` | Hardware timestamping / PTP capabilities. |
| `ethtool -x <if>` | RSS indirection table (how flows spread across queues). |
