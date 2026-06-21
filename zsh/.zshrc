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
# Restore the saved snapshot once per server lifetime, the first time tl/ta runs.
# The @restored flag means a later `tk` stays killed, and `tn` (which never calls
# this) always gives a fresh session — but `tn foo` then `tl` still brings the rest back.
# Restore the saved snapshot exactly once per boot, the first time tl/ta runs.
# The marker lives in XDG_RUNTIME_DIR (/tmp fallback) so it survives killing
# every session but resets on reboot. tn never calls this, so a fresh tn -- and
# a tk'd session -- never come back; but `tn foo` then `tl` still restores the rest.
function _tmux_restore() {
    local marker="${XDG_RUNTIME_DIR:-/tmp}/tmux-restored-$UID"
    [ -e "$marker" ] && return
    local restore="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
    [ -x "$restore" ] || return
    : > "$marker"
    tmux start-server 2>/dev/null
    tmux run-shell "$restore" 2>/dev/null
    for _ in 1 2 3 4 5; do tmux has-session 2>/dev/null && break; sleep 0.2; done
}
function tl() { _tmux_restore; tmux ls 2>/dev/null || echo "no tmux sessions"; }                   # list sessions
function ta() { _tmux_restore; tmux attach ${1:+-t "$1"} 2>/dev/null || tmux new ${1:+-s "$1"}; }  # attach (last if omitted)
alias tn='tmux new -s'                  # tn <name>  — new session
alias tk='tmux kill-session -t'         # tk <name>  — kill session

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

# _renderdot <file.md>: render a markdown cheat sheet as clean, man-like text.
# The .md files stay as GitHub tables; this strips the markup for the terminal.
function _renderdot() {
    local rc="$HOME/.zshrc"
    local doc="${rc:A:h:h}/$1"   # follow symlink -> repo root
    [ -f "$doc" ] || doc="$HOME/dotfiles/$1"
    if [ ! -f "$doc" ]; then echo "${1} not found"; return 1; fi
    awk '
        function strip(s){ gsub(/`/,"",s); gsub(/\*\*/,"",s); return s }
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        BEGIN { b="\033[1m"; r="\033[0m"; col=20 }
        /^#[^#]/        { next }                                       # drop H1 title
        /^## /          { sub(/^## /,""); printf "\n" b toupper($0) r "\n"; next }
        /^\|[ ]*:?-+/   { next }                                       # table separator
        /^\|/ {
            split($0,a,"|"); c=trim(a[2]); d=trim(a[3])
            if (c=="Command" || c=="Keys") next                       # generic header
            c=strip(c); d=strip(d)
            if (d=="")               { printf "\n" b c r "\n"; next }  # subheader (e.g. dot cmds)
            else if (length(c)<=col)   printf "  %-*s  %s\n", col, c, d
            else                       printf "  %s\n  %*s  %s\n", c, col, "", d
            next
        }
        /^[ \t]*$/      { next }                                       # drop blank lines
        { print "  " strip($0) }                                      # prose
    ' "$doc" | less -FRX
}
function helpdot() { _renderdot MAIN_cmds.md; }      # main cheat sheet
function termdot() { _renderdot terminal_cmds.md; }  # terminal cmds I forget
function perfdot() { _renderdot perf_cmds.md; }      # perf / measurement cmds

# updatedot: pull the latest dotfiles, re-run install.sh, reload the shell.
function updatedot() {
    git clone https://github.com/tristanx86/dotfiles.git ~/dotfiles 2>/dev/null || (cd ~/dotfiles && git fetch && git reset --hard origin/main) && chmod +x ~/dotfiles/install.sh && ~/dotfiles/install.sh && exec zsh
}

# ── Firedancer Development ───────────────────────────
# Firedancer build/run, config management, and pktgen tooling live in sibling
# files next to this one in the repo. Resolve this file's real directory (it's
# symlinked into $HOME) and source them.
DOTFILES_ZSH_DIR="${${(%):-%x}:A:h}"
for _f in firedancer firedancer-config firedancer-pktgen; do
    [ -r "$DOTFILES_ZSH_DIR/$_f.zsh" ] && source "$DOTFILES_ZSH_DIR/$_f.zsh"
done
unset _f

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

# ── Prompt Configuration ─────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ── Zoxide Initialization ────────────────────────────
# Replaces 'z' plugin for faster, algorithm-based directory jumping.
# Must be initialized at the end of the file.
eval "$(zoxide init zsh)"
export PATH="$HOME/.local/bin:$PATH"
