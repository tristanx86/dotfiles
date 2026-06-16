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
#   tree | code1 (67%) / cmd (33%) | code2 | [ cmd / cmd / htop ]
# A file tree, two terminal columns (the left one split with a command pane
# below), then a right column of two command panes plus htop.
# Run inside tmux (needs tmux >= 3.1 for %).
function fdwork() {
    if [ -z "$TMUX" ]; then
        echo "fdwork must run inside tmux. Start a session first:  tn <name>   (or attach: ta)"
        return 1
    fi
    local dir="$PWD"
    local tree rest cmdcol code1 code2 codecmd cmd1 cmd2 htop
    local mon='command -v htop >/dev/null && htop || top'

    # Columns: tree (~9%) | code area (~61%, 2 cols) | command column (~30%).
    tree=$(tmux new-window   -P -F '#{pane_id}' -n dev -c "$dir")
    rest=$(tmux split-window -h -t "$tree" -l 91% -P -F '#{pane_id}' -c "$dir")
    cmdcol=$(tmux split-window -h -t "$rest" -l 33% -P -F '#{pane_id}' -c "$dir")

    # Code area -> two terminal columns; left column gets a command pane below.
    code1="$rest"
    code2=$(tmux split-window -h -t "$code1" -l 50% -P -F '#{pane_id}' -c "$dir")
    codecmd=$(tmux split-window -v -t "$code1" -l 33% -P -F '#{pane_id}' -c "$dir")

    # Command column -> two command panes stacked above htop.
    cmd1="$cmdcol"
    cmd2=$(tmux split-window -v -t "$cmd1" -l 66% -P -F '#{pane_id}' -c "$dir")
    htop=$(tmux split-window -v -t "$cmd2" -l 50% -P -F '#{pane_id}' -c "$dir")

    tmux send-keys -t "$tree" 'nvim .' C-m     # nvim-tree file explorer
    tmux send-keys -t "$htop" "$mon" C-m       # code/cmd columns stay as plain shells
    tmux select-pane -t "$code1"
}

# helpdot: render the cheat sheet in a pager (resolves the repo via ~/.zshrc).
function helpdot() {
    local rc="$HOME/.zshrc"
    local doc="${rc:A:h:h}/KEYBINDINGS.md"   # follow symlink -> repo root
    [ -f "$doc" ] || doc="$HOME/dotfiles/KEYBINDINGS.md"
    if [ ! -f "$doc" ]; then echo "helpdot: KEYBINDINGS.md not found"; return 1; fi
    if command -v glow >/dev/null; then glow -p "$doc"
    elif command -v bat >/dev/null; then bat --style=plain --paging=always -l md "$doc"
    else less -R "$doc"; fi
}

# updatedot: pull the latest dotfiles, re-run install.sh, reload the shell.
function updatedot() {
    git clone https://github.com/tristanx86/dotfiles.git ~/dotfiles 2>/dev/null || (cd ~/dotfiles && git fetch && git reset --hard origin/main) && chmod +x ~/dotfiles/install.sh && ~/dotfiles/install.sh && exec zsh
}

# ── Firedancer Development ───────────────────────────
# Which firedancer binary the fd commands drive. Switch with `switchfd <name>`,
# stored per-device in an untracked file (defaults to firedancer-dev).
FD_BIN_FILE="$HOME/.config/dotfiles/fdbin"
_fdbin() { cat "$FD_BIN_FILE" 2>/dev/null || echo firedancer-dev; }
# Make target(s) for the current binary. fddev also needs the solana target.
_fdtarget() { case "$(_fdbin)" in fddev) echo "fddev solana";; *) echo "$(_fdbin)";; esac; }

# switchfd <name>: pick the firedancer binary makefd/devfd/pktfd/... use.
function switchfd() {
    if [ -z "$1" ]; then
        echo "Current firedancer binary: $(_fdbin) (make target: $(_fdtarget))"
        echo "Usage: switchfd <firedancer-dev|fddev|firedancer|...>"
        return 0
    fi
    mkdir -p "$(dirname "$FD_BIN_FILE")"
    echo "$1" > "$FD_BIN_FILE"
    echo "Firedancer binary set to: $1 (make target: $(_fdtarget))"
}

function makefd()    { make -j $(_fdtarget); }
function pullfd()    { git pull && git submodule update && ./deps.sh && make -j $(_fdtarget); }
function pktfd()     { sudo "$(_fdbin)" pktgen --config "$(_fdconfig)"; }
function devfd()     { sudo "$(_fdbin)" dev --config "$(_fdconfig)"; }
function flamefd()   { sudo "$(_fdbin)" flame --config "$(_fdconfig)"; }    # perf flamegraph
function metricsfd() { sudo "$(_fdbin)" metrics --config "$(_fdconfig)"; }  # Prometheus metrics

# ── Firedancer Config Files ──────────────────────────
# Manage multiple config.toml files and remember which is active (per-device,
# untracked). Falls back to ~/config.toml when no managed config is selected.
FD_CONFIG_DIR="$HOME/.config/dotfiles/fdconfigs"
FD_CONFIG_FILE="$HOME/.config/dotfiles/fdconfig"   # stores the active config's name
_fdconfig() {
    local name; name=$(cat "$FD_CONFIG_FILE" 2>/dev/null)
    if [ -n "$name" ] && [ -f "$FD_CONFIG_DIR/$name.toml" ]; then
        echo "$FD_CONFIG_DIR/$name.toml"
    else
        echo "$HOME/config.toml"
    fi
}

# cfgfd: create / list / delete / switch firedancer config files.
function cfgfd() {
    mkdir -p "$FD_CONFIG_DIR"
    local cmd="$1"; (( $# )) && shift
    local current; current=$(cat "$FD_CONFIG_FILE" 2>/dev/null)
    case "$cmd" in
        new)
            [ -z "$1" ] && { echo "Usage: cfgfd new <name>"; return 1; }
            local dest="$FD_CONFIG_DIR/$1.toml"
            [ -e "$dest" ] && { echo "cfgfd: config '$1' already exists"; return 1; }
            if [ -f "$(_fdconfig)" ]; then cp "$(_fdconfig)" "$dest"; else touch "$dest"; fi
            echo "$1" > "$FD_CONFIG_FILE"
            echo "Created and switched to config: $1 ($dest)"
            ${EDITOR:-nvim} "$dest"
            ;;
        ls)
            local found=0 f n
            for f in "$FD_CONFIG_DIR"/*.toml(N); do
                found=1; n="${f:t:r}"
                [ "$n" = "$current" ] && echo "* $n (active)" || echo "  $n"
            done
            (( found )) || echo "No configs yet. Create one with 'cfgfd new <name>'."
            ;;
        rm)
            [ -z "$1" ] && { echo "Usage: cfgfd rm <name>"; return 1; }
            [ -f "$FD_CONFIG_DIR/$1.toml" ] || { echo "cfgfd: no config named '$1'"; return 1; }
            rm "$FD_CONFIG_DIR/$1.toml"
            [ "$current" = "$1" ] && rm -f "$FD_CONFIG_FILE"   # fall back to ~/config.toml
            echo "Deleted config: $1"
            ;;
        use)
            [ -z "$1" ] && { echo "Usage: cfgfd use <name>"; return 1; }
            [ -f "$FD_CONFIG_DIR/$1.toml" ] || { echo "cfgfd: no config named '$1'. Run 'cfgfd ls'."; return 1; }
            echo "$1" > "$FD_CONFIG_FILE"
            echo "Switched to config: $1 ($FD_CONFIG_DIR/$1.toml)"
            ;;
        "")
            ${EDITOR:-nvim} "$(_fdconfig)"
            ;;
        cur)
            echo "Active config: $(_fdconfig)"
            ;;
        *)
            echo "Usage: cfgfd | cfgfd {new <name>|ls|rm <name>|use <name>|cur}"
            return 1
            ;;
    esac
}

# ── Hardware & Performance Tuning ────────────────────
alias disable-ht="echo off | sudo tee /sys/devices/system/cpu/smt/control"
alias enable-ht="echo on | sudo tee /sys/devices/system/cpu/smt/control"

# topo: CPU topology + NUMA layout, for tile pinning decisions.
function topo() {
    echo "== Summary =="
    lscpu | grep -E '^(Architecture|CPU\(s\)|Thread|Core|Socket|NUMA|Model name)'
    echo
    echo "== Per-CPU: CPU NODE SOCKET CORE ONLINE MAXMHZ (same CORE = HT siblings) =="
    lscpu -e=CPU,NODE,SOCKET,CORE,ONLINE,MAXMHZ
    echo
    echo "Isolated CPUs: $(cat /sys/devices/system/cpu/isolated 2>/dev/null || echo '?')"
    if command -v numactl >/dev/null; then
        echo
        echo "== NUMA =="
        numactl -H
    fi
}

# Release reserved hugepages (2MB and 1GB) on NUMA node0
function relmemfd() {
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
    make -j $(_fdtarget)
}

# ── Prompt Configuration ─────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ── Zoxide Initialization ────────────────────────────
# Replaces 'z' plugin for faster, algorithm-based directory jumping.
# Must be initialized at the end of the file.
eval "$(zoxide init zsh)"
export PATH="$HOME/.local/bin:$PATH"
