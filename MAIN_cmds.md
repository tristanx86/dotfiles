# Cheat Sheet

## Shell

| Command | Action |
| :--- | :--- |
| `s` / `sfd` | SSH to main / secondary dev server. See `hostdot`. |
| `switchfd [name]` | Pick the firedancer binary `*fd` commands drive. |
| `makefd` | Build the binary's make target (`fddev` also builds solana). |
| `pullfd` | `git pull`, submodules, `deps.sh`, build. |
| `branchfd <name>` | Pull, checkout `tristan/tristanx86/<name>`, build. |
| `devfd` / `pktfd` | Run the binary's `dev` / `pktgen` with `~/config.toml`. |
| `testnetfd` | Run the binary with `--testnet --config`. |
| `pktfd setup` | Configure firedancer NIC route/ARP + optional DPDK pktgen; prompts for NICs as needed. |
| `pktfd restore` | Undo `setup`'s vfio-pci bind — return the pktgen NIC to its kernel driver. |
| `flamefd` | Capture a `perf` flamegraph. |
| `metricsfd` | Print Prometheus metrics. |
| `memfd` | Print the binary's memory usage report. |
| `initfd` | `configure init all` with active config. |
| `finifd` | `configure fini all` with active config. |
| `relmemfd` | Release 2MB & 1GB hugepages. |

| cfd cmds | |
| :--- | :--- |
| `cfd` | Edit active config. |
| `cfd new <name>` | Create config (seeded from active) and switch. |
| `cfd ls` | List configs; `*` marks active. |
| `cfd <name>` | Switch active config. |
| `cfd rm <name>` | Delete a config. |
| `cfd path` | Print active config path. |

| dot cmds | |
| :--- | :--- |
| `helpdot` | This main cheat sheet. |
| `termdot` | Terminal cmds I forget. |
| `perfdot` | Perf / measurement cmds. |
| `hostdot` | Host / SSH management cmds (`s`/`sfd`). |
| `updatedot` | Pull dotfiles, re-run `install.sh`, reload shell. |

## Navigation

| Keys | Action |
| :--- | :--- |
| `Ctrl h/j/k/l` | Move between Neovim splits and tmux panes. |
| `Shift ←/→` | Switch tmux windows. |
| `gd` | Go to definition (Neovim). |

## Tmux

Prefix = `F1`. Manage sessions from the shell:

| Command | Action |
| :--- | :--- |
| `tn <name>` | New session. |
| `ta [name]` | Attach (last if omitted). |
| `tl` / `tk <name>` | List / kill sessions. |
| `fdwork` | Ultrawide dev window: tree, 2 terminal columns, right column of 2 panes + htop. |

Inside a session:

| Keys | Action |
| :--- | :--- |
| `Prefix h/j/k/l` | Split pane left / down / up / right. |
| `Prefix z` | Zoom pane. |
| `Prefix c` / `d` | New window / detach. |
| `Prefix r` | Reload config. |
| `Cmd Enter` / `Cmd T` | New Kitty window / tab. |

## Neovim

Leader = `F1`.

| Keys | Action |
| :--- | :--- |
| `Leader ff` / `fg` / `fb` | Find files / live grep / buffers. |
| `Leader e` | Diagnostics float. |
| `Leader d` / `db` / `du` | Debug: continue / breakpoint / UI. |
| `:Git` | Fugitive. |

Tree: `y` copies abs path, `Enter` copies `nvim <path>`.
