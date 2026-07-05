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
source "$DOTFILES_DIR/install-packages.sh"

# Detect distro family by available package manager (used below, and to know
# which package list to check when snapshotting original machine state).
DISTRO_FAMILY="" RHEL_PKG=""
if [[ "$OS" == "Linux" ]]; then
    if command -v apt-get &>/dev/null; then
        DISTRO_FAMILY="debian"
    elif command -v dnf &>/dev/null; then
        DISTRO_FAMILY="rhel"; RHEL_PKG="dnf"
    elif command -v yum &>/dev/null; then
        DISTRO_FAMILY="rhel"; RHEL_PKG="yum"
    else
        DISTRO_FAMILY="unknown"
    fi
fi

# Where we cache cheap "did this already happen recently" markers so re-runs
# (updatedot) don't redo expensive network-bound work every single time.
STATE_DIR="$HOME/.cache/dotfiles"
mkdir -p "$STATE_DIR"

# -----------------------------------------------------------------------------
# Original-state snapshot (for `wipedot`)
# -----------------------------------------------------------------------------
# Written exactly once — the very first time install.sh runs on this machine,
# before anything below installs a single package — so wipedot can later tell
# apart "dotfiles installed this" (safe to remove) from "this was already
# here" (leave it alone). Re-running install.sh/updatedot never overwrites it.
# Machines that already had dotfiles installed before this existed have no
# snapshot to work from; wipedot handles that as a degraded, best-effort case.
ORIGINAL_STATE_FILE="$STATE_DIR/original-state"
if [ ! -f "$ORIGINAL_STATE_FILE" ]; then
    echo "[Wipedot] First run on this machine — recording original state for wipedot..."
    {
        echo "ORIGINAL_OS=$OS"
        echo "ORIGINAL_DISTRO_FAMILY=$DISTRO_FAMILY"
        echo "ORIGINAL_SHELL=$SHELL"

        preexisting=()
        case "$DISTRO_FAMILY" in
            debian)
                for pkg in "${DEBIAN_PKGS[@]+"${DEBIAN_PKGS[@]}"}" "${DEBIAN_PERF_PKGS[@]+"${DEBIAN_PERF_PKGS[@]}"}" "${DEBIAN_NEOVIM_PKGS[@]+"${DEBIAN_NEOVIM_PKGS[@]}"}"; do
                    dpkg -s "$pkg" >/dev/null 2>&1 && preexisting+=("$pkg")
                done
                ;;
            rhel)
                for pkg in "${RHEL_PKGS[@]+"${RHEL_PKGS[@]}"}" "${RHEL_EXTRA_PKGS[@]+"${RHEL_EXTRA_PKGS[@]}"}" "${RHEL_PERF_PKGS[@]+"${RHEL_PERF_PKGS[@]}"}" "${RHEL_NEOVIM_PKGS[@]+"${RHEL_NEOVIM_PKGS[@]}"}"; do
                    rpm -q "$pkg" >/dev/null 2>&1 && preexisting+=("$pkg")
                done
                ;;
        esac
        if [[ "$OS" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
            for pkg in "${BREW_FORMULAE[@]+"${BREW_FORMULAE[@]}"}"; do
                brew list --formula "$pkg" >/dev/null 2>&1 && preexisting+=("$pkg")
            done
            for pkg in "${BREW_CASKS[@]+"${BREW_CASKS[@]}"}" "${BREW_CASKS_SOFT[@]+"${BREW_CASKS_SOFT[@]}"}"; do
                brew list --cask "$pkg" >/dev/null 2>&1 && preexisting+=("$pkg")
            done
        fi
        echo "PREEXISTING_PKGS=\"${preexisting[*]}\""

        # None of these are apt/dnf/brew packages, so they need their own
        # presence check — install.sh only ever acts on each when it's
        # *absent* (every _task_* below is a "return 0 if already there"
        # guard), so "was it here before" is the only fact wipedot needs; it
        # never has to worry about dotfiles having upgraded/modified one that
        # already existed.
        _p() { [ -e "$1" ] && echo 1 || echo 0; }
        echo "PREEXISTING_OHMYZSH=$(_p "$HOME/.oh-my-zsh")"
        echo "PREEXISTING_CARGO=$(command -v cargo >/dev/null 2>&1 && echo 1 || echo 0)"
        echo "PREEXISTING_KITTY=$(command -v kitty >/dev/null 2>&1 && echo 1 || echo 0)"
        echo "PREEXISTING_FONT=$(_p "$FONT_DIR/FiraCode")"
        echo "PREEXISTING_TREESITTER_CLI=$(command -v tree-sitter >/dev/null 2>&1 && echo 1 || echo 0)"
        echo "PREEXISTING_TPM=$(_p "$HOME/.tmux/plugins/tpm")"
        echo "PREEXISTING_P10K=$(_p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k")"
        echo "PREEXISTING_NVIM_DATA=$(_p "${XDG_DATA_HOME:-$HOME/.local/share}/nvim")"

        if [[ "$OS" == "Darwin" ]]; then
            iterm_guid_val="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null)"
            if [ -n "$iterm_guid_val" ]; then
                echo "ITERM_GUID_WAS_SET=1"
                echo "ORIGINAL_ITERM_GUID=\"$iterm_guid_val\""
            else
                echo "ITERM_GUID_WAS_SET=0"
            fi
            iterm_clip_val="$(defaults read com.googlecode.iterm2 AllowClipboardAccess 2>/dev/null)"
            if [ -n "$iterm_clip_val" ]; then
                echo "ITERM_CLIP_WAS_SET=1"
                echo "ORIGINAL_ITERM_CLIP=\"$iterm_clip_val\""
            else
                echo "ITERM_CLIP_WAS_SET=0"
            fi
        fi
    } > "$ORIGINAL_STATE_FILE"
fi

# _sha256 <file>: portable hash (Linux has sha256sum, macOS has shasum).
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        cksum "$1" | awk '{print $1}'
    fi
}

# _apt_update_if_stale <max_age_hours>: `apt-get update` hits every configured
# mirror over the network, so only do it if the lists are actually old enough
# to matter — updatedot re-running this daily shouldn't re-fetch them every time.
_apt_update_if_stale() {
    local max_age_hours=$1 stamp="$STATE_DIR/apt-update-stamp"
    if [ -f "$stamp" ]; then
        local age_h=$(( ($(date +%s) - $(stat -c %Y "$stamp")) / 3600 ))
        if [ "$age_h" -lt "$max_age_hours" ]; then
            echo "  (package lists refreshed ${age_h}h ago, < ${max_age_hours}h — skipping apt-get update)"
            return 0
        fi
    fi
    sudo apt-get update -y && touch "$stamp"
}

# _bg_run <name> <func>: run <func> (no args) in the background, capturing its
# output to a per-job log, so independent installs with no shared state
# (network fetches, git clones) can happen concurrently instead of one at a
# time. Never use this for anything touching apt/dnf/yum — package managers
# take an exclusive lock, so "parallel" calls there just serialize anyway
# while adding a new way to fail.
BG_PIDS=() BG_NAMES=() BG_LOGS=()
_bg_run() {
    local name=$1 log="$STATE_DIR/bg-$1.log"
    # stdin -> /dev/null: these should all be non-interactive (-y/--unattended),
    # so if one unexpectedly wants input it fails fast instead of hanging
    # silently in the background on the terminal's stdin.
    ( "$1" ) </dev/null >"$log" 2>&1 &
    BG_PIDS+=("$!"); BG_NAMES+=("$name"); BG_LOGS+=("$log")
}

# _bg_wait: wait for every _bg_run job queued so far, printing its captured
# output and flagging failures, then reset the queue.
_bg_wait() {
    local i pid name log rc
    for i in "${!BG_PIDS[@]}"; do
        pid=${BG_PIDS[$i]}; name=${BG_NAMES[$i]}; log=${BG_LOGS[$i]}
        wait "$pid"; rc=$?
        [ -s "$log" ] && cat "$log"
        [ "$rc" -ne 0 ] && echo "[WARNING] $name failed (exit $rc) — see above."
    done
    BG_PIDS=() BG_NAMES=() BG_LOGS=()
}

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
    brew install "${BREW_FORMULAE[@]}"
    brew install --cask "${BREW_CASKS[@]}"
    brew install --cask "${BREW_CASKS_SOFT[@]}" 2>/dev/null || true

    # iTerm2: install TokyoNight Dynamic Profile + configure preferences so nothing
    # needs to be done manually inside the app.
    ITERM_DIR="$HOME/Library/Application Support/iTerm2"
    if [ -d "$ITERM_DIR" ]; then
        mkdir -p "$ITERM_DIR/DynamicProfiles"
        cp "$DOTFILES_DIR/iterm2/TokyoNight.json" "$ITERM_DIR/DynamicProfiles/"
        # Set TokyoNight as the default profile (GUID matches the JSON file).
        defaults write com.googlecode.iterm2 "Default Bookmark Guid" \
            -string "fd0c77e8-7bb3-4b8c-9d2f-1a2b3c4d5e6f"
        # Allow OSC 52 clipboard access so copy/paste works over SSH.
        defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
        echo "[MacOS] iTerm2 configured (TokyoNight profile set as default, clipboard enabled)."
        echo "        Restart iTerm2 for preference changes to take effect."
    fi

# -----------------------------------------------------------------------------
# Linux Setup
# -----------------------------------------------------------------------------
elif [[ "$OS" == "Linux" ]]; then
    [[ "$DISTRO_FAMILY" == "unknown" ]] && \
        echo "[WARNING] No supported package manager found (apt-get/dnf/yum). Skipping system packages."

    # ---- Debian / Ubuntu -----------------------------------------------------
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        echo "[Linux/Debian] Updating package lists..."
        _apt_update_if_stale 24

        echo "[Linux/Debian] Installing System & Dev Dependencies..."
        sudo apt-get install -y "${DEBIAN_PKGS[@]}"

        # Performance / measurement tooling (perf_cmds.md)
        echo "[Linux/Debian] Installing performance / measurement tooling..."
        sudo apt-get install -y "${DEBIAN_PERF_PKGS[@]}" \
            || echo "[WARNING] some perf tools unavailable; install manually (see perf_cmds.md)."

        # Install Neovim from unstable PPA — only add + refresh the repo the
        # first time; once it's there, apt's normal cache (see
        # _apt_update_if_stale above) keeps it fresh without a forced update.
        if ! grep -rq "neovim-ppa/unstable" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
            echo "[Linux/Debian] Adding Neovim Unstable PPA..."
            sudo add-apt-repository -y ppa:neovim-ppa/unstable
            sudo apt-get update -y
        fi
        echo "[Linux/Debian] Installing/Upgrading Neovim..."
        sudo apt-get install -y "${DEBIAN_NEOVIM_PKGS[@]}"

        # Kernel-version-specific perf tools (graceful failure for non-matching kernels)
        sudo apt-get install -y linux-tools-$(uname -r) || \
            echo "[WARNING] Could not install linux-tools-$(uname -r); perf may still work via linux-tools-generic."

        # Debian/Ubuntu installs fd as 'fdfind'; Neovim telescope expects 'fd'
        if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
            sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
        fi

    # ---- Red Hat / Fedora / Rocky Linux / AlmaLinux / CentOS ----------------
    elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        echo "[Linux/RHEL] Detected ${RHEL_PKG}-based system."

        # Enable EPEL on non-Fedora systems (provides zoxide, btop, bpftrace, bcc-tools, etc.)
        DISTRO_ID="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"
        if [[ "$DISTRO_ID" != "fedora" ]]; then
            echo "[Linux/RHEL] Enabling EPEL repository..."
            sudo "$RHEL_PKG" install -y epel-release \
                || echo "[WARNING] epel-release unavailable; some packages may be missing."
        fi

        echo "[Linux/RHEL] Installing System & Dev Dependencies..."
        # Key name differences vs Debian: gcc gcc-c++ make (≈build-essential),
        # pkgconf-pkg-config (≈pkg-config), openssl-devel (≈libssl-dev),
        # python3 python3-pip (≈python3-venv — venv is bundled in python3 on RHEL)
        sudo "$RHEL_PKG" install -y "${RHEL_PKGS[@]}"
        # kitty-terminfo is in Fedora repos and EPEL; soft-install so SSH sessions
        # with TERM=xterm-kitty are recognised (clipboard, true colour, etc.).
        sudo "$RHEL_PKG" install -y "${RHEL_EXTRA_PKGS[@]}" 2>/dev/null \
            || echo "[INFO] kitty-terminfo not available; TERM=xterm-kitty may not be recognised."

        # Performance / measurement tooling
        # Key name differences: perf (≈linux-tools-*), bcc-tools (≈bpfcc-tools)
        echo "[Linux/RHEL] Installing performance / measurement tooling..."
        sudo "$RHEL_PKG" install -y "${RHEL_PERF_PKGS[@]}" \
            || echo "[WARNING] some perf tools unavailable; install manually (see perf_cmds.md)."

        # Install Neovim; fall back to pre-built binary from GitHub if not in repos
        echo "[Linux/RHEL] Installing Neovim..."
        if ! sudo "$RHEL_PKG" install -y "${RHEL_NEOVIM_PKGS[@]}" 2>/dev/null; then
            echo "[Linux/RHEL] Falling back to pre-built Neovim binary from GitHub..."
            NVIM_ARCHIVE="/tmp/nvim-linux-x86_64.tar.gz"
            curl -L https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz \
                -o "$NVIM_ARCHIVE" \
                && sudo tar -C /usr/local -xzf "$NVIM_ARCHIVE" --strip-components=1 \
                && rm -f "$NVIM_ARCHIVE" \
                || echo "[WARNING] Neovim install failed; install manually."
        fi

        # On RHEL/Fedora, fd-find installs the binary as 'fd' (no symlink needed)
        if ! command -v fd &>/dev/null; then
            sudo "$RHEL_PKG" install -y fd-find 2>/dev/null \
                || echo "[WARNING] fd not installed; Neovim file picker may not work."
        fi
    fi

    # ---- Shared Linux (distro-agnostic) --------------------------------------
    # Independent network installs, no shared state between them — run
    # concurrently instead of one after another.
    _task_rust() {
        command -v cargo &>/dev/null && return 0
        echo "[Linux] Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    }
    _task_kitty() {
        command -v kitty &>/dev/null && return 0
        echo "[Linux] Installing Kitty Terminal..."
        curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
        mkdir -p ~/.local/bin
        ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
    }
    _task_nerdfont() {
        [[ -d "$FONT_DIR/FiraCode" ]] && return 0
        echo "[Linux] Installing FiraCode Nerd Font..."
        mkdir -p "$FONT_DIR/FiraCode"
        wget -q -P "$FONT_DIR/FiraCode" \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
        unzip -q "$FONT_DIR/FiraCode/FiraCode.zip" -d "$FONT_DIR/FiraCode"
        rm -f "$FONT_DIR/FiraCode/FiraCode.zip"
        fc-cache -f
    }
    _bg_run _task_rust
    _bg_run _task_kitty
    _bg_run _task_nerdfont
    _bg_wait
fi

# -----------------------------------------------------------------------------
# tree-sitter CLI, Oh-My-Zsh, Powerlevel10k, TPM
# -----------------------------------------------------------------------------
# Four independent installs (npm global package + three git-based installs),
# none depending on each other — run them concurrently. (The tree-sitter-cli
# sudo fallback relies on the credential cache from `sudo -v` at the top of
# this script on Linux; on macOS it's essentially never hit since brew's npm
# prefix is user-writable.)
_task_treesitter_cli() {
    command -v tree-sitter >/dev/null 2>&1 && return 0
    echo "[Neovim] Installing tree-sitter CLI..."
    # Plain install works where the npm prefix is user-writable (brew); fall
    # back to sudo for system prefixes (apt's /usr/local).
    npm install -g tree-sitter-cli 2>/dev/null \
        || sudo npm install -g tree-sitter-cli \
        || { echo "[WARNING] tree-sitter CLI install failed; nvim-treesitter parsers won't build."; return 1; }
}
_task_ohmyzsh() {
    [ -d "$HOME/.oh-my-zsh" ] && return 0
    echo "[Shell] Installing Oh-My-Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}
_task_p10k() {
    local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    [ -d "$dir" ] && return 0
    echo "[Shell] Installing Powerlevel10k Theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$dir"
}
_task_tpm() {
    local dir="$HOME/.tmux/plugins/tpm"
    [ -d "$dir" ] && return 0
    echo "[Tmux] Installing TPM (Tmux Plugin Manager)..."
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$dir"
}
_bg_run _task_treesitter_cli
_bg_run _task_ohmyzsh
_bg_run _task_tpm
_bg_wait

# p10k's target lives *inside* oh-my-zsh's directory tree (custom/themes/...),
# so it isn't actually independent of _task_ohmyzsh — it has to run after that
# batch completes, not alongside it (a concurrent clone could leave
# ~/.oh-my-zsh non-empty right as oh-my-zsh's own clone tries to populate it).
_task_p10k

# -----------------------------------------------------------------------------
# Shell Configuration & Symlinking
# -----------------------------------------------------------------------------

# Set zsh as the login shell.
# chsh may fail on LDAP/managed accounts; we fall back to an exec zsh line in
# .bashrc so interactive sessions still land in zsh regardless.
ZSH_BIN="$(command -v zsh 2>/dev/null)"
if [ -n "$ZSH_BIN" ]; then
    # zsh must be in /etc/shells before chsh will accept it.
    if ! grep -qx "$ZSH_BIN" /etc/shells 2>/dev/null; then
        echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
    fi
    if chsh -s "$ZSH_BIN" "$USER" 2>/dev/null || sudo chsh -s "$ZSH_BIN" "$USER" 2>/dev/null; then
        echo "[Shell] Login shell set to $ZSH_BIN."
    else
        echo "[Shell] chsh failed (managed account?). .bashrc will exec zsh as fallback."
    fi
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
        local backup="${dest}.backup.$(date +%s)"
        echo "[Backup] Moving existing $dest to $backup"
        mv "$dest" "$backup"
    fi

    ln -sf "$src" "$dest"
    echo "[Link] $dest -> $src"
}

echo "==== Linking Configuration Files ===="
create_symlink "$DOTFILES_DIR/zsh/.zshrc"        "$HOME/.zshrc"
create_symlink "$DOTFILES_DIR/zsh/.p10k.zsh"     "$HOME/.p10k.zsh"
create_symlink "$DOTFILES_DIR/zsh/.bashrc"        "$HOME/.bashrc"
create_symlink "$DOTFILES_DIR/zsh/.bash_profile"  "$HOME/.bash_profile"
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

# Sync Neovim plugins to the lockfile and build treesitter parsers, so updatedot
# is self-contained (restore switches nvim-treesitter to its `main` branch).
# Both steps are skipped when there's nothing to do — a headless nvim start
# plus a plugin sync isn't free, and updatedot may run this daily.
if command -v nvim >/dev/null 2>&1; then
    NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    TS_LANGS="c cpp lua rust python bash"

    # A new nvim build can break ABI compatibility with already-compiled
    # parsers / installed plugins, so an nvim version bump forces a resync
    # even if the lockfile/parser files themselves look unchanged.
    NVIM_VER_STAMP="$STATE_DIR/nvim-version"
    CUR_NVIM_VER="$(nvim --version | head -1)"
    NVIM_VER_CHANGED=0
    [ "$CUR_NVIM_VER" != "$(cat "$NVIM_VER_STAMP" 2>/dev/null)" ] && NVIM_VER_CHANGED=1

    LOCK_FILE="$DOTFILES_DIR/nvim/lazy-lock.json"
    LOCK_STAMP="$STATE_DIR/lazy-lock.sha256"
    LOCK_HASH=""
    [ -f "$LOCK_FILE" ] && LOCK_HASH="$(_sha256 "$LOCK_FILE")"
    if [ "$NVIM_VER_CHANGED" = 1 ] || [ ! -d "$NVIM_DATA_DIR/lazy" ] || [ "$LOCK_HASH" != "$(cat "$LOCK_STAMP" 2>/dev/null)" ]; then
        echo "[Neovim] Syncing plugins to lockfile..."
        yes '' | nvim --headless "+Lazy! restore" +qa 2>/dev/null
        echo "$LOCK_HASH" > "$LOCK_STAMP"
    else
        echo "[Neovim] Plugins already match the lockfile — skipping Lazy restore."
    fi

    TS_MISSING=0
    for lang in $TS_LANGS; do
        [ -f "$NVIM_DATA_DIR/site/parser/${lang}.so" ] || TS_MISSING=1
    done
    if [ "$NVIM_VER_CHANGED" = 1 ] || [ "$TS_MISSING" = 1 ]; then
        echo "[Neovim] Building treesitter parsers..."
        yes '' | nvim --headless "+lua require('nvim-treesitter').install({'c','cpp','lua','rust','python','bash'}):wait(300000)" +qa 2>/dev/null \
            || echo "[WARNING] treesitter parser build failed; open nvim and run :TSUpdate."
    else
        echo "[Neovim] Treesitter parsers already installed — skipping build."
    fi

    echo "$CUR_NVIM_VER" > "$NVIM_VER_STAMP"
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

echo "==== Setup Complete ===="
