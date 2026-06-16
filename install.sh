#!/usr/bin/env bash
# We removed the '-e' flag so the script will NOT crash on errors.
# It will attempt to power through and do as much as it can.
set -uo pipefail

# -----------------------------------------------------------------------------
# Configuration & Variables
# -----------------------------------------------------------------------------
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS="$(uname -s)"
FONT_DIR="$HOME/.local/share/fonts"

echo "==== Initializing Environment Setup ===="

# Ask for the administrator password upfront and keep it alive
if [[ "$OS" == "Linux" ]]; then
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# -----------------------------------------------------------------------------
# MacOS Setup
# -----------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
    echo "[MacOS] Detected. Checking Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "[MacOS] Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    echo "[MacOS] Installing Core Utilities & Dev Tools..."
    brew install git zsh wget node ripgrep fd neovim cmake llvm cppcheck rustup-init tmux gdb zoxide htop btop
    brew install --cask kitty font-fira-code-nerd-font

# -----------------------------------------------------------------------------
# Linux Setup
# -----------------------------------------------------------------------------
elif [[ "$OS" == "Linux" ]]; then
    echo "[Linux] Detected. Updating package lists..."
    sudo apt-get update -y

    echo "[Linux] Installing System & Dev Dependencies..."
    sudo apt-get install -y build-essential git zsh curl wget unzip tar \
                        xclip nodejs npm ripgrep fd-find python3-venv \
                        cmake clang lldb lld cppcheck pkg-config libssl-dev \
                        tmux gdb zoxide htop btop

    # Install Rust if not present
    if ! command -v cargo &>/dev/null; then
        echo "[Linux] Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi

    # Symlink fd-find to fd (Neovim expects 'fd')
    if ! command -v fd &>/dev/null; then
        sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi

    # Install Neovim Unstable PPA
    echo "[Linux] Adding Neovim Unstable PPA..."
    sudo add-apt-repository -y ppa:neovim-ppa/unstable
    sudo apt-get update -y
    echo "[Linux] Installing/Upgrading Neovim..."
    sudo apt-get install -y neovim

    # Install Performance Tools (Graceful failure for mainline kernels)
    echo "[Linux] Installing Performance Counters (perf)..."
    sudo apt-get install -y linux-tools-common linux-tools-generic linux-tools-$(uname -r) || \
    echo "[WARNING] Could not install linux-tools via apt. Using manually compiled version."

    # Install Kitty Terminal
    if ! command -v kitty &>/dev/null; then
        echo "[Linux] Installing Kitty Terminal..."
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
        mkdir -p ~/.local/bin
        ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
    fi

    # Install Nerd Fonts
    if [[ ! -d "$FONT_DIR/FiraCode" ]]; then
        echo "[Linux] Installing FiraCode Nerd Font..."
        mkdir -p "$FONT_DIR/FiraCode"
        wget -q --show-progress -P "$FONT_DIR/FiraCode" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
        unzip -q "$FONT_DIR/FiraCode/FiraCode.zip" -d "$FONT_DIR/FiraCode"
        rm -f "$FONT_DIR/FiraCode/FiraCode.zip"
        fc-cache -fv
    fi
fi

# -----------------------------------------------------------------------------
# Shell Configuration & Symlinking
# -----------------------------------------------------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[Shell] Installing Oh-My-Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    echo "[Shell] Installing Powerlevel10k Theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
    echo "[Tmux] Installing TPM (Tmux Plugin Manager)..."
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

create_symlink() {
    local src=$1
    local dest=$2
    mkdir -p "$(dirname "$dest")"
    
    # Check if destination exists
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        # If it is a symlink AND already points to our source, we are good to go
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            return
        fi
        
        # Otherwise, back it up
        echo "[Backup] Moving existing $dest to ${dest}.backup.$(date +%s)"
        mv "$dest" "${dest}.backup.$(date +%s)"
    fi
    
    ln -sf "$src" "$dest"
    echo "[Link] $dest -> $src"
}

echo "==== Linking Configuration Files ===="
create_symlink "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
create_symlink "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
create_symlink "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
create_symlink "$DOTFILES_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"

if [ -d "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
    echo "[Backup] Moving existing Neovim config..."
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.backup.$(date +%s)"
fi
create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

# Install tmux plugins now that .tmux.conf is linked.
if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
    echo "[Tmux] Installing tmux plugins..."
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || echo "[WARNING] tmux plugin install failed; run prefix+I inside tmux."
fi

# -----------------------------------------------------------------------------
# htop / btop preconfiguration
# -----------------------------------------------------------------------------
# These tools rewrite their config on exit, so seed (copy) rather than symlink.
echo "==== Seeding htop / btop configs ===="

seed_config() {
    local src="$1" dest="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
        mv "$dest" "${dest}.backup.$(date +%s)"
        echo "[Backup] Saved existing $dest"
    fi
    cp "$src" "$dest"
    echo "[Config] Seeded $dest"
}

if command -v btop &>/dev/null; then
    seed_config "$DOTFILES_DIR/btop/btop.conf" "$HOME/.config/btop/btop.conf"
fi

# htop >= 3.2 uses named fields; older htop needs the legacy numeric format.
if command -v htop &>/dev/null; then
    HTOP_RC="$HOME/.config/htop/htoprc"
    htver="$(htop --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    if [ -n "$htver" ] && [ "$(printf '%s\n3.2.0\n' "$htver" | sort -V | head -1)" != "3.2.0" ]; then
        echo "[htop] Detected htop $htver (< 3.2); writing legacy numeric-field config..."
        mkdir -p "$(dirname "$HTOP_RC")"
        [ -f "$HTOP_RC" ] && mv "$HTOP_RC" "${HTOP_RC}.backup.$(date +%s)"
        cat > "$HTOP_RC" <<'HTOPRC'
htop_version=3.0.5
config_reader_min_version=2
fields=0 48 17 18 38 39 2 46 47 37 50 1
sort_key=46
sort_direction=-1
hide_kernel_threads=0
hide_userland_threads=0
shadow_other_users=0
show_thread_names=1
show_program_path=0
highlight_base_name=1
highlight_megabytes=1
highlight_threads=1
find_comm_in_cmdline=1
strip_exe_from_cmdline=1
show_merged_command=0
tree_view=0
header_margin=1
detailed_cpu_time=0
cpu_count_from_one=0
show_cpu_usage=1
show_cpu_frequency=1
show_cpu_temperature=1
update_process_names=0
account_guest_in_cpu_meter=0
color_scheme=0
enable_mouse=1
delay=15
hide_function_bar=0
header_layout=two_50_50
column_meters_0=LeftCPUs2 Memory Swap
column_meter_modes_0=1 1 1
column_meters_1=RightCPUs2 Tasks LoadAverage Uptime
column_meter_modes_1=1 2 2 2
HTOPRC
        echo "[Config] Seeded $HTOP_RC (legacy format)"
    else
        seed_config "$DOTFILES_DIR/htop/htoprc" "$HTOP_RC"
    fi
fi

# -----------------------------------------------------------------------------
# Finalization
# -----------------------------------------------------------------------------
echo "==== Changing Default Shell to Zsh ===="
CURRENT_SHELL=$(basename "$SHELL")
if [ "$CURRENT_SHELL" != "zsh" ]; then
    if command -v zsh &>/dev/null; then
        # On Linux use sudo, on Mac run it normally
        if [[ "$OS" == "Linux" ]]; then
            sudo chsh -s "$(which zsh)" "$USER"
        else
            chsh -s "$(which zsh)"
        fi
        echo "[Shell] Default shell changed to Zsh."
    else
        echo "[WARNING] Zsh is not installed. Skipping shell change."
    fi
else
    echo "[Shell] Zsh is already the default shell."
fi

echo "==== Setup Complete ===="
