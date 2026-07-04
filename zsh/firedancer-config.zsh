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

# cfd: create / list / delete / switch firedancer config files.
function cfd() {
    mkdir -p "$FD_CONFIG_DIR"
    local cmd="$1"; (( $# )) && shift
    local current; current=$(cat "$FD_CONFIG_FILE" 2>/dev/null)
    case "$cmd" in
        new)
            [ -z "$1" ] && { echo "Usage: cfd new <name>"; return 1; }
            local dest="$FD_CONFIG_DIR/$1.toml"
            [ -e "$dest" ] && { echo "cfd: config '$1' already exists"; return 1; }
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
            (( found )) || echo "No configs yet. Create one with 'cfd new <name>'."
            ;;
        rm)
            [ -z "$1" ] && { echo "Usage: cfd rm <name>"; return 1; }
            [ -f "$FD_CONFIG_DIR/$1.toml" ] || { echo "cfd: no config named '$1'"; return 1; }
            rm "$FD_CONFIG_DIR/$1.toml"
            [ "$current" = "$1" ] && rm -f "$FD_CONFIG_FILE"   # fall back to ~/config.toml
            echo "Deleted config: $1"
            ;;
        "")
            ${EDITOR:-nvim} "$(_fdconfig)"
            ;;
        path)
            echo "Active config: $(_fdconfig)"
            ;;
        *)
            [ -f "$FD_CONFIG_DIR/$cmd.toml" ] || { echo "cfd: no config named '$cmd'. Run 'cfd ls'."; return 1; }
            echo "$cmd" > "$FD_CONFIG_FILE"
            echo "Switched to config: $cmd ($FD_CONFIG_DIR/$cmd.toml)"
            ;;
    esac
}
