# ── Firedancer Development ───────────────────────────
# Build/run commands for the firedancer validator. Config management lives in
# firedancer-config.zsh; pktgen/loopback setup in firedancer-pktgen.zsh.
#
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

# These were aliases historically; drop any stale alias so re-sourcing .zshrc
# (without a fresh shell) doesn't shadow the functions — an alias would make
# `pktfd setup` expand to `... pktgen ... setup` instead of running the setup.
unalias makefd pullfd pktfd devfd flamefd metricsfd 2>/dev/null

function makefd()    { make -j $(_fdtarget); }
function pullfd()    { git pull && git submodule update && ./deps.sh && make -j $(_fdtarget); }
function devfd()     { sudo "$(_fdbin)" dev --config "$(_fdconfig)"; }
function flamefd()   { sudo "$(_fdbin)" flame --config "$(_fdconfig)"; }    # perf flamegraph
function metricsfd() { sudo "$(_fdbin)" metrics --config "$(_fdconfig)"; }  # Prometheus metrics

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
