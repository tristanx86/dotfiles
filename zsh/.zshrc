# Enable Powerlevel10k instant prompt.
# This block must remain at the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── Environment & Path Configuration ─────────────────
export ZSH="$HOME/.oh-my-zsh"
export EDITOR="nvim"
export VISUAL="nvim"

# Kitty Terminal SSH Fix (Translates custom terminfo for standard servers)
[ "$TERM" = "xterm-kitty" ] && export TERM=xterm-256color

OS="$(uname -s)"

# ── macOS Configuration ──────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
    # Homebrew Setup (Apple Silicon / Intel fallback)
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # Build Flags
    export LDFLAGS="-L$(brew --prefix)/opt/openssl/lib"
    export CPPFLAGS="-I$(brew --prefix)/opt/openssl/include"
    export PATH="$(brew --prefix)/opt/llvm/bin:$PATH"

    # Kitty Terminal Integration
    # 'kitten ssh' automatically propagates terminfo and clipboard capability
    #
    # The SSH target is stored per-device in an untracked file so each machine
    # can point 's' at a different server without editing the dotfiles.
    #   s                connect to the saved server
    #   s user@host      connect to user@host and save it as the new default
    FD_SERVER_FILE="$HOME/.config/dotfiles/server"

    function s() {
        if [ -n "$1" ]; then
            mkdir -p "$(dirname "$FD_SERVER_FILE")"
            echo "$1" > "$FD_SERVER_FILE"
        fi
        if [ ! -s "$FD_SERVER_FILE" ]; then
            echo "No server set. Usage: s user@host (saved for next time)"
            return 1
        fi
        kitty +kitten ssh "$(cat "$FD_SERVER_FILE")"
    }

    # Mosh Integration (Optional: requires 'brew install mosh')
    # Uses the same saved server as 's'.
    function m() {
        if [ ! -s "$FD_SERVER_FILE" ]; then
            echo "No server set. Run 's user@host' first to save one."
            return 1
        fi
        kitty +kitten ssh --kitten=mosh "$(cat "$FD_SERVER_FILE")"
    }

# ── Linux Configuration (Dell/Razer) ─────────────────
elif [[ "$OS" == "Linux" ]]; then
    # Performance Analysis Tools (perf wrappers)
    # Basic cache miss and cycle analysis
    alias pstat="sudo perf stat -e cache-misses,cache-references,cycles,instructions,branches,branch-misses"
    
    # Sampling profiler configuration
    alias precord="sudo perf record -g"
    alias preport="sudo perf report"

    # ── Screen Power Management (X Authority Fix) ────────────────
    # Use these functions to safely turn off the screen power when SSHing.
    function display-off() {
        local AUTH_FILE=$(find /run/user/$(id -u) -name 'Xauthority' 2>/dev/null | head -n 1)
        
        if [ -n "$AUTH_FILE" ]; then
            # Export the XAUTH key and the correct display number (:1 worked)
            export XAUTHORITY=$AUTH_FILE
            export DISPLAY=:1 
            
            echo "Turning display off..."
            xset dpms force off
        else
            echo "ERROR: Xauthority key missing. Ensure the system is logged in locally."
        fi
    }

    # Alias to restore the screen power
    alias display-on="xset dpms force on"
fi

# ── Oh My Zsh Plugins ────────────────────────────────
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins:
# - git: standard git aliases
# - sudo: double-tap ESC to prepend sudo
# Note: 'z' has been removed in favor of zoxide at the EOF.
plugins=(git sudo) 

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# ── Aliases: General ─────────────────────────────────
alias v='nvim'
alias vim='nvim'
alias ll='ls -la'

# ── Aliases: Git ─────────────────────────────────────
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gco='git checkout'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'

# ── Aliases: Session Management ──────────────────────
# Attach to existing 'main' session or create new
alias t="tmux new-session -A -s main"

# 3-pane workspace in the current dir: editor | build shell / htop.
# Re-run to re-attach (works inside or outside tmux).
function fdwork() {
    local session="fd"
    if tmux has-session -t "$session" 2>/dev/null; then
        if [ -n "$TMUX" ]; then tmux switch-client -t "$session"; else tmux attach -t "$session"; fi
        return
    fi
    local dir="$PWD"
    tmux new-session -d -s "$session" -c "$dir" -n dev
    tmux split-window -h  -t "$session:dev"   -c "$dir"   # pane 1: right column
    tmux split-window -v  -t "$session:dev.1" -c "$dir"   # pane 2: bottom-right
    tmux send-keys -t "$session:dev.2" 'command -v htop >/dev/null && htop || top' C-m
    tmux select-pane -t "$session:dev.0"
    tmux send-keys -t "$session:dev.0" 'nvim .' C-m
    if [ -n "$TMUX" ]; then tmux switch-client -t "$session"; else tmux attach -t "$session"; fi
}

# ── Firedancer Development ───────────────────────────
alias makefd="make -j fdctl solana firedancer-dev"
alias pullfd="git pull && git submodule update && ./deps.sh && make -j fdctl solana firedancer-dev"
alias pktfd="sudo firedancer-dev pktgen --config ~/config.toml"
alias devfd="sudo firedancer-dev dev --config ~/config.toml"
alias confd="nvim ~/config.toml"

# ── Hardware & Performance Tuning ────────────────────
alias disable-ht="echo off | sudo tee /sys/devices/system/cpu/smt/control"

# Release reserved hugepages (2MB and 1GB) on NUMA node0
function memfd() {
    echo 0 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
    echo 0 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages
}

function clockspeed() {
    if [ -z "$1" ]; then
        echo "Usage: clockspeed <GHz> (e.g., clockspeed 3.2)"
        return 1
    fi
    sudo cpupower frequency-set -u "${1}GHz" -d "${1}GHz"
}

# ── Firedancer Branch Management ─────────────────────
function branchfd() {
    if [ -z "$1" ]; then
        echo "Usage: branchfd <branch-name>"
        return 1
    fi
    git pull
    git checkout -b "$1" "tristan/tristanx86/$1" || { echo "Error: Branch checkout failed. Make sure the remote branch exists."; return 1; }
    make -j fdctl solana firedancer-dev
}

# ── Prompt Configuration ─────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ── Zoxide Initialization ────────────────────────────
# Replaces 'z' plugin for faster, algorithm-based directory jumping.
# Must be initialized at the end of the file.
eval "$(zoxide init zsh)"
export PATH="$HOME/.local/bin:$PATH"
