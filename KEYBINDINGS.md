# Cheat Sheet

Run `dothelp` to read this in the terminal.

## Shell

| Command | Action |
| :--- | :--- |
| `dothelp` | Show this cheat sheet. |
| `dotupdate` | Pull the latest dotfiles, re-run `install.sh`, reload the shell. |
| `s [user@host]` | SSH to the saved server. Pass `user@host` once to set it (stored in `~/.config/dotfiles/server`). |
| `makefd` | `make -j firedancer-dev`. |
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

## Navigation

| Keys | Action |
| :--- | :--- |
| `Ctrl h/j/k/l` | Move between Neovim splits and tmux panes. |
| `Shift ←/→` | Switch tmux windows. |
| `gd` | Go to definition (Neovim). |

## Tmux

> Prefix key = `F1` (unified with Neovim's leader).

Manage sessions from the shell:

| Command | Action |
| :--- | :--- |
| `tn <name>` | New session. |
| `ta [name]` | Attach (last session if omitted). |
| `tl` | List sessions. |
| `tk <name>` | Kill session. |
| `fdwork` | Ultrawide dev window in the current session: file tree, 2 terminal columns (left split with a command pane below), and a right column of 2 command panes + htop. Run inside tmux. |

Inside a session (Prefix = `F1`):

| Keys | Action |
| :--- | :--- |
| `Prefix h/j/k/l` | Split pane left / down / up / right. |
| `Prefix z` | Zoom pane (toggle). |
| `Prefix c` / `d` | New window / detach. |
| `Prefix r` | Reload config. |
| `Prefix Ctrl-s` / `Ctrl-r` | Save / restore sessions. |
| Mouse drag border | Resize pane. |
| `Cmd Enter` / `Cmd T` | New Kitty window / tab. |

Sessions auto-save and restore across reboots and SSH drops (tmux-continuum).

## Neovim

> Leader key = `F1` (unified with tmux's prefix).

| Keys | Action |
| :--- | :--- |
| `Leader ff` / `fg` / `fb` | Find files / live grep / buffers. |
| `Leader e` | Diagnostics float. |
| `Leader d` / `db` / `du` | Debug: continue / breakpoint / UI. |
| `:NvimTreeToggle` | File explorer. |
| `:Git` | Fugitive. |
