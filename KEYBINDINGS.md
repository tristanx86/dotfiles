# Cheat Sheet

## Shell

| Command | Action |
| :--- | :--- |
| `helpdot` | Show this cheat sheet. |
| `updatedot` | Pull dotfiles, re-run `install.sh`, reload shell. |
| `s [user@host]` | SSH to saved server; pass `user@host` once to set it. |
| `switchfd [name]` | Pick the firedancer binary `*fd` commands drive. |
| `makefd` | Build the binary's make target (`fddev` also builds solana). |
| `pullfd` | `git pull`, submodules, `deps.sh`, build. |
| `branchfd <name>` | Pull, checkout `tristan/tristanx86/<name>`, build. |
| `devfd` / `pktfd` | Run the binary's `dev` / `pktgen` with `~/config.toml`. |
| `pktfd setup` | fd pktgen + optional physical loopback DPDK setup. |
| `flamefd` | Capture a `perf` flamegraph. |
| `metricsfd` | Print Prometheus metrics. |
| `cfgfd` | Edit active config. |
| `cfgfd new <name>` | Create config (seeded from active) and switch. |
| `cfgfd ls` | List configs; `*` marks active. |
| `cfgfd <name>` | Switch active config. |
| `cfgfd rm <name>` | Delete a config. |
| `cfgfd path` | Print active config path. |

## Performance

| Command | Action |
| :--- | :--- |
| `htop` / `btop` | Preconfigured monitors (per-core, kernel threads, CPU% sort). |
| `topo` | CPU topology + NUMA layout for tile pinning. |
| `enable-ht` / `disable-ht` | Toggle hyperthreading. |
| `relmemfd` | Release 2MB & 1GB hugepages. |
| `clockspeed <ghz>` | Pin min/max CPU frequency. |
| `pstat` | `perf stat` — cache misses, cycles, branches. |

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
| `Prefix Ctrl-s` / `Ctrl-r` | Save / restore sessions. |
| `Cmd Enter` / `Cmd T` | New Kitty window / tab. |

## Neovim

Leader = `F1`.

| Keys | Action |
| :--- | :--- |
| `Leader ff` / `fg` / `fb` | Find files / live grep / buffers. |
| `Leader e` | Diagnostics float. |
| `Leader d` / `db` / `du` | Debug: continue / breakpoint / UI. |
| `:NvimTreeToggle` | File explorer. |
| `:Git` | Fugitive. |

Tree: `y` copies abs path, `Enter` copies `nvim <path>`.

## Standard Keybinds (that I sometimes forget)

| Keys | Action |
| :--- | :--- |
| `Ctrl u` | Clear the current input line. |
| `Ctrl w` | Delete previous word. |
| `Ctrl a` / `Ctrl e` | Jump to start / end of line. |
| `Ctrl k` | Delete to end of line. |
| `Ctrl l` | Clear screen. |
| `Ctrl r` | Reverse history search. |
| `Ctrl c` / `Ctrl d` | Cancel input / EOF (exit shell). |
