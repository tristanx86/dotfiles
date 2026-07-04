# Tristan Carter's macOS/Linux Development Setup

Sets up my configured development environment with Neovim, tmux, Zsh, and Kitty. Designed for macOS and Linux.

## Prerequisites

Ensure `git` is installed before running the setup.

* **macOS:** Running `git` in the terminal will automatically prompt you to install the Command Line Tools if it's missing.
* **Debian/Ubuntu:** `sudo apt update && sudo apt install git -y`
* **Red Hat / Fedora / Rocky / Alma:** `sudo dnf install git -y`

## Installation

Copy and paste this one-liner into your terminal to clone (or update) the repository and run the setup script automatically:

```bash
git clone https://github.com/tristanx86/dotfiles.git ~/dotfiles 2>/dev/null || (cd ~/dotfiles && git fetch && git reset --hard origin/main) && chmod +x ~/dotfiles/install.sh && ~/dotfiles/install.sh && exec zsh
```

## Reduced / client setup

For a restricted machine. `install-client.sh` never uses `sudo` — it's
mainly for setting up the terminal and host/SSH management (`s`/`sfd`, see
`host_cmds.md` / `hostdot`).

```bash
git clone https://github.com/tristanx86/dotfiles.git ~/dotfiles 2>/dev/null || (cd ~/dotfiles && git fetch && git reset --hard origin/main) && chmod +x ~/dotfiles/install-client.sh && ~/dotfiles/install-client.sh && exec zsh
```
