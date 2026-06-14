# Environment Cheat Sheet

## 1. Daily Firedancer Workflow
*These commands are available instantly in your Zsh prompt.*

| Command | Action |
| :--- | :--- |
| **`s`** | **SSH into the saved server.** First run `s user@host` once per device to set it (e.g. `s tristan@myserver`); afterwards just `s`. Target is stored in `~/.config/dotfiles/server`. |
| **`t`** | **Attach / Create Tmux session** (Run this right after `s`) |
| **`pullfd`** | Full sync: `git pull`, submodules, `deps.sh`, and `make -j ...` |
| **`makefd`** | Fast build: `make -j fdctl solana firedancer-dev` |
| **`branchfd <name>`**| Pull, checkout `tristan/tristanx86/<name>`, and build |
| **`devfd`** | Run `sudo firedancer-dev dev` with `config.toml` |
| **`pktfd`** | Run `sudo firedancer-dev pktgen` with `config.toml` |
| **`confd`** | Open `config.toml` in Neovim |

---

## 2. Hardware & Performance Tuning
*System-level commands for profiling and bare-metal testing.*

| Command | Action |
| :--- | :--- |
| **`disable-ht`** | Turn off Hyperthreading via `/sys/devices/.../smt/control` |
| **`memfd`** | Release reserved 2MB & 1GB hugepages on NUMA `node0` (sets `nr_hugepages` to 0) |
| **`clockspeed <x>`** | Pin CPU frequency (e.g., `clockspeed 3.2` sets min/max to 3.2GHz) |
| **`pstat`** | Run `perf stat` for cache misses, cycles, branches, etc. |
| **`precord`** / **`preport`**| Run `perf record -g` for sampling / `perf report` to view |

---

## 3. Seamless Navigation
*How to move around at the speed of light.*

| Shortcut | Action | Tool |
| :--- | :--- | :--- |
| **`Ctrl` + `h/j/k/l`** | **Move between Neovim splits *and* Tmux panes** | Global |
| **`Shift` + `→ / ←`** | **Fast switch Tmux windows** (tabs) | Tmux |
| **`gd`** | Go to definition under cursor | Neovim |
| **`<leader>e`** | Show floating diagnostics / errors | Neovim |
| **`<leader>ff`** | Fuzzy find files | Neovim |
| **`<leader>fg`** | Live grep / search inside all files | Neovim |

---

## 4. Window & Pane Splitting
*Managing your screen real estate.*
> **Tmux Prefix = `Ctrl+A`**

| Shortcut | Action | Tool |
| :--- | :--- | :--- |
| **`Prefix` + `h/j/k/l`** | **Split pane** left / down / up / right | Tmux |
| **`Prefix` + `Shift` + `H/J/K/L`** | **Resize pane** in that direction | Tmux |
| **`Prefix` + `Z`** | **Zoom** (fullscreen) current pane, press again to unzoom | Tmux |
| **`Prefix` + `C`** | Create a new Tmux window | Tmux |
| **`Prefix` + `D`** | Detach from session (leaves everything running) | Tmux |
| **`Cmd` + `Enter` / `T`** | Open a new local Kitty Window or Tab | Kitty |

---

## 5. Editor Extras (Neovim)

| Shortcut | Action |
| :--- | :--- |
| **`<leader>fb`** | Find open buffers |
| **`:NvimTreeToggle`** | Open the sidebar file explorer |
| **`:Git`** | Open Fugitive (Git interface) |
