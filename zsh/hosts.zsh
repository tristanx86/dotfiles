# ── Host / SSH Management ─────────────────────────────
# Two roles, each just a pointer to a user@host address, stored per-device
# (untracked) so each machine can point at different servers:
#   main      the one 's' connects to — your primary coding box
#   secondary the one bare 'sfd' connects to — e.g. a fleet host for
#             long-running tests
# 'sfd' also keeps a named registry so you can refer to hosts by name instead
# of typing the address every time. Resolution: an arg to 's' or 'sfd' that
# matches a registered name resolves to that host's address; otherwise it's
# used as a literal user@host (so 's' keeps working with raw addresses that
# were never registered).
HOSTS_DIR="$HOME/.config/dotfiles/hosts"          # named registry: <name>.host -> user@host
HOST_MAIN_FILE="$HOME/.config/dotfiles/server"    # main dev server's address
HOST_DEV_FILE="$HOME/.config/dotfiles/hostdev"    # secondary/dev host's address

_hostresolve() {
    local arg=$1
    if [ -f "$HOSTS_DIR/$arg.host" ]; then
        cat "$HOSTS_DIR/$arg.host"
    else
        echo "$arg"
    fi
}

# kitten ssh propagates terminfo + OSC 52 clipboard; only available in Kitty.
_sshconnect() {
    local addr=$1
    if [[ "$TERM_PROGRAM" == "kitty" ]]; then
        kitty +kitten ssh "$addr"
    else
        ssh "$addr"
    fi
}

# s: ssh to the main dev server.
#   s                connect to the main dev server
#   s user@host      set main to a raw address and connect
#   s name           set main to a registered 'sfd' host and connect
function s() {
    if [ -n "$1" ]; then
        mkdir -p "$(dirname "$HOST_MAIN_FILE")"
        _hostresolve "$1" > "$HOST_MAIN_FILE"
    fi
    if [ ! -s "$HOST_MAIN_FILE" ]; then
        echo "No main dev server set. Usage: s user@host (or s <name>, saved for next time)"
        return 1
    fi
    _sshconnect "$(cat "$HOST_MAIN_FILE")"
}

# sfd: registry of named hosts, plus the "secondary" dev host.
#   sfd                  ssh to the secondary host
#   sfd name             ssh to a registered host and set it as secondary
#   sfd new name [addr]  register a host (prompts for addr if omitted)
#   sfd rm name          delete a registered host
#   sfd ls               list registered hosts; (s)/(dev) mark main/secondary
function sfd() {
    mkdir -p "$HOSTS_DIR"
    local cmd="$1"; (( $# )) && shift
    case "$cmd" in
        new)
            [ -z "$1" ] && { echo "Usage: sfd new <name> [user@host]"; return 1; }
            local name="$1"; shift
            local dest="$HOSTS_DIR/$name.host"
            [ -e "$dest" ] && { echo "sfd: host '$name' already exists"; return 1; }
            local addr="$1"
            if [ -z "$addr" ]; then
                read -rp "Address for '$name' (user@host): " addr
                [ -z "$addr" ] && { echo "sfd: no address given"; return 1; }
            fi
            echo "$addr" > "$dest"
            echo "Registered host: $name ($addr)"
            ;;
        rm)
            [ -z "$1" ] && { echo "Usage: sfd rm <name>"; return 1; }
            [ -f "$HOSTS_DIR/$1.host" ] || { echo "sfd: no host named '$1'"; return 1; }
            rm "$HOSTS_DIR/$1.host"
            echo "Deleted host: $1"
            ;;
        ls)
            local main_addr dev_addr; main_addr=$(cat "$HOST_MAIN_FILE" 2>/dev/null); dev_addr=$(cat "$HOST_DEV_FILE" 2>/dev/null)
            local found=0 f n a tag
            for f in "$HOSTS_DIR"/*.host(N); do
                found=1; n="${f:t:r}"; a=$(cat "$f")
                if [ -n "$main_addr" ] && [ "$a" = "$main_addr" ]; then
                    tag=" (s)"
                elif [ -n "$dev_addr" ] && [ "$a" = "$dev_addr" ]; then
                    tag=" (dev)"
                else
                    tag=""
                fi
                echo "  $n ($a)$tag"
            done
            (( found )) || echo "No hosts yet. Add one with 'sfd new <name> [user@host]'."
            ;;
        "")
            if [ ! -s "$HOST_DEV_FILE" ]; then
                echo "No secondary host set. Run 'sfd <name>' to connect and set one."
                return 1
            fi
            _sshconnect "$(cat "$HOST_DEV_FILE")"
            ;;
        *)
            [ -f "$HOSTS_DIR/$cmd.host" ] || { echo "sfd: no host named '$cmd'. Run 'sfd new $cmd [user@host]' or 'sfd ls'."; return 1; }
            cat "$HOSTS_DIR/$cmd.host" > "$HOST_DEV_FILE"
            _sshconnect "$(cat "$HOST_DEV_FILE")"
            ;;
    esac
}
