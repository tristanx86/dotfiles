# ── Firedancer Development ───────────────────────────
# Build/run commands for the firedancer validator. Config management lives in
# firedancer-config.zsh; pktgen/loopback setup in firedancer-pktgen.zsh.
#
# Which firedancer binary the fd commands drive. Switch with `switchfd <name>`,
# stored per-device in an untracked file (defaults to firedancer-dev).
FD_BIN_FILE="$HOME/.config/dotfiles/fdbin"
_fdbin() { cat "$FD_BIN_FILE" 2>/dev/null || echo firedancer-dev; }
# Resolve binary to absolute path so sudo can find it regardless of secure_path (needed on RHEL/Fedora).
_fdbinpath() { command -v "$(_fdbin)" || _fdbin; }
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

# These were aliases historically; drop any stale alias so re-sourcing .zshrc
# (without a fresh shell) doesn't shadow the functions — an alias would make
# `pktfd setup` expand to `... pktgen ... setup` instead of running the setup.
unalias makefd updatefd pktfd devfd testnetfd flamefd metricsfd memfd initfd finifd 2>/dev/null

function makefd()    { make -j $(_fdtarget); }
function devfd() {
    if [ "$1" = gdb ]; then shift; sudo gdb --args "$(_fdbinpath)" dev --config "$(_fdconfig)" "$@"; return; fi
    sudo "$(_fdbinpath)" dev --config "$(_fdconfig)"
}
function testnetfd() {
    if [ "$1" = gdb ]; then shift; sudo gdb --args "$(_fdbinpath)" --testnet --config "$(_fdconfig)" "$@"; return; fi
    sudo "$(_fdbinpath)" --testnet --config "$(_fdconfig)"
}
function flamefd()   { sudo "$(_fdbinpath)" flame --config "$(_fdconfig)"; }    # perf flamegraph
function metricsfd() { sudo "$(_fdbinpath)" metrics --config "$(_fdconfig)"; }  # Prometheus metrics
function memfd()     { sudo "$(_fdbinpath)" mem --config "$(_fdconfig)"; }      # memory usage report
function initfd()    { sudo "$(_fdbinpath)" configure init all --config "$(_fdconfig)"; }
function finifd()    { sudo "$(_fdbinpath)" configure fini all --config "$(_fdconfig)"; }

# ── Firedancer Fork Sync ──────────────────────────────
# updatefd: sync local + origin main to upstream's main. Only ever touches
# main — refuses to run with any uncommitted/staged changes (regardless of
# which branch they're on), and switches back to your original branch after,
# so whatever you were working on is left untouched.
function updatefd() {
    if [ -n "$(git status --porcelain)" ]; then
        echo "updatefd: working tree has uncommitted changes — commit or stash first."
        return 1
    fi
    local ans
    read "ans?Force-sync main to upstream? [Y/n] "
    case "$ans" in n|N|no|No) echo "Aborted."; return 1;; esac

    local cur
    cur=$(git branch --show-current)
    git fetch upstream || return 1
    git checkout main || return 1
    git reset --hard upstream/main || return 1
    git push --force origin main
    local status=$?
    if [ -n "$cur" ] && [ "$cur" != main ]; then
        git checkout "$cur"
    fi
    return $status
}
