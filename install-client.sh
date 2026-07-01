#!/usr/bin/env bash
# Minimal setup for a client / jump machine (corporate MacBook, restricted env).
# Only symlinks dotfiles and configures tools that are already installed.
# Does NOT install Homebrew packages or run curl-pipe-sh installers.
#
# What this sets up:
#   - zsh config (oh-my-zsh + p10k, installed via git if missing)
#   - tmux config (if tmux is installed)
#   - nvim config (if nvim is installed)
#   - iTerm2 TokyoNight profile + default profile + clipboard access
#   - The `s` / `m` functions for connecting to your dev server
#
# Run on the server itself:  bash ~/dotfiles/install.sh

set -uo pipefail
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
create_symlink() {
    local src=$1 dest=$2
    mkdir -p "$(dirname "$dest")"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        return  # already correct
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        local backup="${dest}.backup.$(date +%s)"
        echo "[Backup] $dest -> $backup"
        mv "$dest" "$backup"
    fi
    ln -s "$src" "$dest"
    echo "[Link]   $dest -> $src"
}

try_git_clone() {
    local url=$1 dest=$2 label=$3
    if [ -d "$dest" ]; then return 0; fi
    echo "[Client] Installing $label..."
    git clone --depth=1 "$url" "$dest" \
        || echo "[WARN] $label install failed — network may be restricted. Install manually later."
}

# -----------------------------------------------------------------------------
# Shell config
# -----------------------------------------------------------------------------
create_symlink "$DOTFILES_DIR/zsh/.zshrc"       "$HOME/.zshrc"
create_symlink "$DOTFILES_DIR/zsh/.p10k.zsh"    "$HOME/.p10k.zsh"
create_symlink "$DOTFILES_DIR/zsh/.bashrc"       "$HOME/.bashrc"
create_symlink "$DOTFILES_DIR/zsh/.bash_profile" "$HOME/.bash_profile"

# Set zsh as the login shell (macOS: chsh should always work).
ZSH_BIN="$(command -v zsh 2>/dev/null)"
if [ -n "$ZSH_BIN" ] && [ "$SHELL" != "$ZSH_BIN" ]; then
    chsh -s "$ZSH_BIN" 2>/dev/null \
        && echo "[Shell] Login shell set to $ZSH_BIN." \
        || echo "[WARN] chsh failed — run manually: chsh -s $ZSH_BIN"
fi

# oh-my-zsh (git clone, no curl-pipe-sh)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[Client] Installing Oh-My-Zsh..."
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" \
        || echo "[WARN] oh-my-zsh install failed. Install manually: https://ohmyz.sh"
fi

# Powerlevel10k theme
try_git_clone \
    https://github.com/romkatv/powerlevel10k.git \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" \
    "Powerlevel10k"

# -----------------------------------------------------------------------------
# tmux (only if installed)
# -----------------------------------------------------------------------------
if command -v tmux &>/dev/null; then
    create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
    try_git_clone \
        https://github.com/tmux-plugins/tpm \
        "$HOME/.tmux/plugins/tpm" \
        "TPM (tmux plugin manager)"
else
    echo "[Skip]   tmux not found — skipping tmux config."
fi

# -----------------------------------------------------------------------------
# nvim (only if installed)
# -----------------------------------------------------------------------------
if command -v nvim &>/dev/null; then
    create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
else
    echo "[Skip]   nvim not found — skipping nvim config."
fi

# -----------------------------------------------------------------------------
# iTerm2
# -----------------------------------------------------------------------------
ITERM_DIR="$HOME/Library/Application Support/iTerm2"
if [ -d "$ITERM_DIR" ]; then
    mkdir -p "$ITERM_DIR/DynamicProfiles"
    cp "$DOTFILES_DIR/iterm2/TokyoNight.json" "$ITERM_DIR/DynamicProfiles/"
    defaults write com.googlecode.iterm2 "Default Bookmark Guid" \
        -string "fd0c77e8-7bb3-4b8c-9d2f-1a2b3c4d5e6f"
    defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
    echo "[Client] iTerm2 configured (TokyoNight default, clipboard enabled). Restart iTerm2."
else
    echo "[Skip]   iTerm2 not found — skipping iTerm2 config."
fi

# -----------------------------------------------------------------------------
# Dev server shortcut
# -----------------------------------------------------------------------------
SERVER_FILE="$HOME/.config/dotfiles/server"
if [ ! -s "$SERVER_FILE" ]; then
    echo ""
    read -rp "Dev server address (user@host, or Enter to skip): " _server
    if [ -n "$_server" ]; then
        mkdir -p "$(dirname "$SERVER_FILE")"
        echo "$_server" > "$SERVER_FILE"
        echo "[Client] Server saved — use 's' to connect."
    fi
fi

# -----------------------------------------------------------------------------
echo ""
echo "Client setup done. Run:  exec zsh"
