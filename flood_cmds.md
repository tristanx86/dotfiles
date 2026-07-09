# Flood Load Generation

`floodfd` load-tests a remote firedancer validator from a *separate* box —
same idea as `pktfd`'s DPDK pktgen, but aimed at a target over the wire
instead of a physical-loopback rig. Always sends 64B (min-sized) UDP packets
at dport 9000. Two engines, chosen explicitly each run:

- `floodfd dpdk` — DPDK pktgen (userspace, needs a NIC bound to vfio-pci or Mellanox/mlx5).
- `floodfd kernel` — the in-kernel pktgen module (no DPDK/hugepages needed), with a target-Mpps rate limit and a live Mpps monitor.

| Command | Action |
| :--- | :--- |
| `floodfd setup` | Pick the sending NIC, enter the destination IP; pings it and resolves the MAC from ARP (also a reachability check). Saved per-machine. |
| `floodfd dpdk` | Installs DPDK + builds Pktgen-DPDK from source if missing (asks first), binds the NIC (vfio-pci, skipped for Mellanox) + reserves hugepages, then launches DPDK pktgen at the saved target. Drops you at pktgen's prompt — run `start 0` and `set 0 rate <pct>` yourself. |
| `floodfd kernel` | Configure in-kernel pktgen threads (top-down cores, like `pktfd`) at a target Mpps (or MAX), start the flood, and show a live Mpps counter. |
| `floodfd stop` | Stop the in-kernel pktgen flood (`floodfd kernel`'s Ctrl-C only stops watching, not the traffic). |
| `floodfd restore` | Undo `floodfd dpdk`'s vfio-pci bind — return the NIC to its kernel driver. |

Standalones: `floodsd`
