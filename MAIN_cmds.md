# Cheat Sheet

## Shell

- `s [user@host]` — SSH to saved server; pass `user@host` once to set it.
- `switchfd [name]` — Pick the firedancer binary `*fd` commands drive.
- `makefd` — Build the binary's make target (`fddev` also builds solana).
- `pullfd` — `git pull`, submodules, `deps.sh`, build.
- `branchfd <name>` — Pull, checkout `tristan/tristanx86/<name>`, build.
- `devfd` / `pktfd` — Run the binary's `dev` / `pktgen` with `~/config.toml`.
- `pktfd setup` — fd pktgen + optional physical loopback DPDK setup.
- `flamefd` — Capture a `perf` flamegraph.
- `metricsfd` — Print Prometheus metrics.
- `relmemfd` — Release 2MB & 1GB hugepages.
- `cfgfd` — Edit active config.
- `cfgfd new <name>` — Create config (seeded from active) and switch.
- `cfgfd ls` — List configs; `*` marks active.
- `cfgfd <name>` — Switch active config.
- `cfgfd rm <name>` — Delete a config.
- `cfgfd path` — Print active config path.

dot cmds:

- `helpdot` — This main cheat sheet.
- `termdot` — Terminal cmds I forget.
- `perfdot` — Perf / measurement cmds.
- `updatedot` — Pull dotfiles, re-run `install.sh`, reload shell.

## Navigation

- `Ctrl h/j/k/l` — Move between Neovim splits and tmux panes.
- `Shift ←/→` — Switch tmux windows.
- `gd` — Go to definition (Neovim).

## Tmux

Prefix = `F1`. Manage sessions from the shell:

- `tn <name>` — New session.
- `ta [name]` — Attach (last if omitted).
- `tl` / `tk <name>` — List / kill sessions.
- `fdwork` — Ultrawide dev window: tree, 2 terminal columns, right column of 2 panes + htop.

Inside a session:

- `Prefix h/j/k/l` — Split pane left / down / up / right.
- `Prefix z` — Zoom pane.
- `Prefix c` / `d` — New window / detach.
- `Prefix r` — Reload config.
- `Prefix Ctrl-s` / `Ctrl-r` — Save / restore sessions.
- `Cmd Enter` / `Cmd T` — New Kitty window / tab.

## Neovim

Leader = `F1`.

- `Leader ff` / `fg` / `fb` — Find files / live grep / buffers.
- `Leader e` — Diagnostics float.
- `Leader d` / `db` / `du` — Debug: continue / breakpoint / UI.
- `:NvimTreeToggle` — File explorer.
- `:Git` — Fugitive.

Tree: `y` copies abs path, `Enter` copies `nvim <path>`.
