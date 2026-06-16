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
    # Cache miss / cycle analysis
    alias pstat="sudo perf stat -e cache-misses,cache-references,cycles,instructions,branches,branch-misses"

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

# ── Tmux ─────────────────────────────────────────────
alias tl='tmux ls'                      # list sessions
alias tn='tmux new -s'                  # tn <name>  — new session
alias tk='tmux kill-session -t'         # tk <name>  — kill session
function ta() { tmux attach ${1:+-t "$1"}; }   # ta [name] — attach (last if omitted)

# fdwork: ultrawide dev window in the CURRENT session. Layout (left -> right):
#   tree | term | term | term | [ cmd / cmd / cmd / htop ]
# A narrow file tree, three tall terminals, then a right column of three short
# stacked command panes plus htop. Run inside tmux (needs tmux >= 3.1 for %).
function fdwork() {
    if [ -z "$TMUX" ]; then
        echo "fdwork must run inside tmux. Start a session first:  tn <name>   (or attach: ta)"
        return 1
    fi
    local dir="$PWD"
    local tree rest cmdcol code1 code2 code3 cmd1 cmd2 cmd3 htop
    local mon='command -v htop >/dev/null && htop || top'

    # Columns: tree (~6%) | code area (~64%) | command column (~30%).
    tree=$(tmux new-window   -P -F '#{pane_id}' -n dev -c "$dir")
    rest=$(tmux split-window -h -t "$tree" -l 94% -P -F '#{pane_id}' -c "$dir")
    cmdcol=$(tmux split-window -h -t "$rest" -l 34% -P -F '#{pane_id}' -c "$dir")

    # Code area -> three editor columns.
    code1="$rest"
    code2=$(tmux split-window -h -t "$code1" -l 66% -P -F '#{pane_id}' -c "$dir")
    code3=$(tmux split-window -h -t "$code2" -l 50% -P -F '#{pane_id}' -c "$dir")

    # Command column -> three short panes stacked above htop.
    cmd1="$cmdcol"
    cmd2=$(tmux split-window -v -t "$cmd1" -l 75% -P -F '#{pane_id}' -c "$dir")
    cmd3=$(tmux split-window -v -t "$cmd2" -l 66% -P -F '#{pane_id}' -c "$dir")
    htop=$(tmux split-window -v -t "$cmd3" -l 50% -P -F '#{pane_id}' -c "$dir")

    tmux send-keys -t "$tree" 'nvim .' C-m     # nvim-tree file explorer
    tmux send-keys -t "$htop" "$mon" C-m       # code columns stay as plain shells
    tmux select-pane -t "$code1"
}

# dothelp: render the cheat sheet in a pager (resolves the repo via ~/.zshrc).
function dothelp() {
    local rc="$HOME/.zshrc"
    local doc="${rc:A:h:h}/KEYBINDINGS.md"   # follow symlink -> repo root
    [ -f "$doc" ] || doc="$HOME/dotfiles/KEYBINDINGS.md"
    if [ ! -f "$doc" ]; then echo "dothelp: KEYBINDINGS.md not found"; return 1; fi
    if command -v glow >/dev/null; then glow -p "$doc"
    elif command -v bat >/dev/null; then bat --style=plain --paging=always -l md "$doc"
    else less -R "$doc"; fi
}

# dotupdate: pull the latest dotfiles, re-run install.sh, reload the shell.
function dotupdate() {
    git clone https://github.com/tristanx86/dotfiles.git ~/dotfiles 2>/dev/null || (cd ~/dotfiles && git fetch && git reset --hard origin/main) && chmod +x ~/dotfiles/install.sh && ~/dotfiles/install.sh && exec zsh
}

# ── Firedancer Development ───────────────────────────
alias makefd="make -j firedancer-dev"
alias pullfd="git pull && git submodule update && ./deps.sh && make -j firedancer-dev"
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
    make -j firedancer-dev
}

# ── Prompt Configuration ─────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ── Zoxide Initialization ────────────────────────────
# Replaces 'z' plugin for faster, algorithm-based directory jumping.
# Must be initialized at the end of the file.
eval "$(zoxide init zsh)"
export PATH="$HOME/.local/bin:$PATH"
