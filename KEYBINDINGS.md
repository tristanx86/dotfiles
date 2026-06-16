# Cheat Sheet

## Starter keys — both are `F1`

Shortcuts are chords: tap the starter, release, then tap the action key (no holding).

- **Prefix** (tmux) — starts tmux pane/window commands.
- **Leader** (Neovim) — starts custom Neovim shortcuts.

Both map to `F1`, so `Prefix h` means `F1` then `h`, and `Leader ff` means `F1` then `f` `f`. F1 is a real key, so this works on any keyboard.

## Shell

| Command | Action |
| :--- | :--- |
| `s [user@host]` | SSH to the saved server. Pass `user@host` once to set it (stored in `~/.config/dotfiles/server`). |
| `t` | Attach / create the `main` tmux session. |
| `fdwork` | 3-pane workspace in the current dir: editor, build shell, `htop`. Re-run to re-attach. |
| `makefd` | `make -j fdctl solana firedancer-dev`. |
| `pullfd` | `git pull`, submodules, `deps.sh`, then build. |
| `branchfd <name>` | Pull, checkout `tristan/tristanx86/<name>`, build. |
| `devfd` / `pktfd` | Run `firedancer-dev dev` / `pktgen` with `~/config.toml`. |
| `confd` | Edit `~/config.toml`. |

## Performance

| Command | Action |
| :--- | :--- |
| `htop` / `btop` | Preconfigured monitors: per-core meters, per-process core column, kernel threads shown, 0-based core IDs, CPU% sort. |
| `disable-ht` | Disable hyperthreading. |
| `memfd` | Release 2MB & 1GB hugepages on NUMA node0. |
| `clockspeed <ghz>` | Pin min/max CPU frequency. |
| `pstat` | `perf stat` — cache misses, cycles, branches. |
| `precord` / `preport` | `perf record -g` / `perf report`. |

## Navigation

| Keys | Action |
| :--- | :--- |
| `Ctrl h/j/k/l` | Move between Neovim splits and tmux panes. |
| `Shift ←/→` | Switch tmux windows. |
| `gd` | Go to definition. |
| `Leader ff` / `fg` / `fb` | Find files / live grep / buffers. |

## Tmux — Prefix = `F1`

| Keys | Action |
| :--- | :--- |
| `Prefix h/j/k/l` | Split pane left / down / up / right. |
| `Prefix z` | Zoom pane (toggle). |
| `Prefix c` / `d` | New window / detach. |
| `Prefix r` | Reload config. |
| `Prefix Ctrl-s` / `Ctrl-r` | Save / restore sessions. |
| Mouse drag border | Resize pane. |
| `Cmd Enter` / `Cmd T` | New Kitty window / tab. |

Sessions auto-save and restore across reboots and SSH drops (tmux-continuum). Plugins are managed by TPM; `install.sh` sets it up, or reinstall with `~/.tmux/plugins/tpm/bin/install_plugins`.

## Neovim

| Keys | Action |
| :--- | :--- |
| `Leader e` | Diagnostics float. |
| `Leader m` / `mr` / `mc` | `:make` / run / clean. |
| `Leader d` / `db` / `du` | Debug: continue / breakpoint / UI. |
| `Leader v` | Valgrind `./main`. |
| `:NvimTreeToggle` | File explorer. |
| `:Git` | Fugitive. |
