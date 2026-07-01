# Bash login shells don't source .bashrc automatically — pull it in here so
# the exec-zsh fallback fires on SSH logins too.
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
