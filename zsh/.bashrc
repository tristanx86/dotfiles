# Switch to zsh for interactive shells — fires when chsh hasn't taken effect yet
# or the login shell is still bash for any reason.
[[ $- == *i* ]] && command -v zsh >/dev/null 2>&1 && exec zsh -l

# ── Everything below only runs when zsh is genuinely unavailable ──────────────

export EDITOR="nvim"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Homebrew (macOS)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Rust
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# Aliases
alias ll='ls -la'
alias v='nvim'
alias vim='nvim'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gco='git checkout'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias disable-ht="echo off | sudo tee /sys/devices/system/cpu/smt/control"
alias enable-ht="echo on | sudo tee /sys/devices/system/cpu/smt/control"
