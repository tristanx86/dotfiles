# ── Firedancer Development ───────────────────────────
# Build/run commands for the firedancer validator. Config management lives in
# firedancer-config.zsh; pktgen/loopback setup in firedancer-pktgen.zsh.
#
# Which firedancer binary the fd commands drive. Switch with `switchfd <name>`,
# stored per-device in an untracked file (defaults to firedancer-dev).
FD_BIN_FILE="$HOME/.config/dotfiles/fdbin"
_fdbin() { cat "$FD_BIN_FILE" 2>/dev/null || echo firedancer-dev; }
# Resolve binary to absolute path so sudo can find it regardless of secure_path
# (needed on RHEL/Fedora). Falls back to the repo's own build output
# (build/<target>/<compiler>/bin/<name>, e.g. build/native/gcc/bin/firedancer-dev)
# when the binary isn't on PATH — some distros (Rocky et al.) don't get that
# directory on PATH any other way, which otherwise means manually symlinking
# the binary somewhere on PATH before every fd command works.
_fdbinpath() {
    local name; name=$(_fdbin)
    local found; found=$(command -v "$name" 2>/dev/null)
    [ -n "$found" ] && { echo "$found"; return; }
    local candidates=(build/*/*/bin/$name(N.Om[1]))
    if [ ${#candidates} -ge 1 ]; then
        echo "$PWD/${candidates[1]}"
        return
    fi
    echo "$name"
}
# Make target(s) for the current binary. fddev also needs the solana target.
_fdtarget() { case "$(_fdbin)" in fddev) echo "fddev solana";; *) echo "$(_fdbin)";; esac; }

# _fd_clip <text>: copy text to the *local* clipboard via OSC 52, which
# round-trips over SSH (iTerm2's AllowClipboardAccess is enabled in
# install.sh) — same mechanism nvim/init.lua uses for its own OSC 52
# clipboard. Terminal.app doesn't support OSC 52, so it gets pbcopy instead.
# Wrapped in tmux's passthrough sequence when inside tmux, or the escape
# never reaches the outer terminal.
function _fd_clip() {
    local text=$1
    if [ "$TERM_PROGRAM" = "Apple_Terminal" ] && command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$text" | pbcopy
        return
    fi
    local b64
    b64=$(printf '%s' "$text" | base64 | tr -d '\n')
    if [ -n "$TMUX" ]; then
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$b64"
    else
        printf '\033]52;c;%s\a' "$b64"
    fi
}

# _fd_show <cmd...>: print the command — quoted so it's safe to paste back
# verbatim (e.g. prefixed with `perf record --` or wrapped in `gdb --args`)
# — and copy it to the clipboard via _fd_clip. Does NOT execute it; you paste
# and run it yourself (optionally wrapped in another tool first).
function _fd_show() {
    local printed
    printed=$(printf '%q ' "$@")
    printed=${printed% }
    echo "$printed"
    _fd_clip "$printed"
}

# _fd_dispatch <mode> <cmd...>: shared body for every fd function's `cmd`
# subcommand (devfd cmd, pktfd cmd, ...) — <mode> is the caller's un-shifted
# $1. "cmd" shows+copies <cmd...> via _fd_show instead of running it;
# anything else (typically empty) just executes it.
function _fd_dispatch() {
    local mode=$1; shift
    if [ "$mode" = cmd ]; then _fd_show "$@"; else "$@"; fi
}

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

# Every function below takes an optional `cmd` first argument (see
# _fd_dispatch): plain `devfd` runs the validator, `devfd cmd` just shows +
# copies the command it would have run.
function makefd()    { make -j $(_fdtarget); }
function devfd() {
    if [ "$1" = gdb ]; then shift; sudo gdb -q --args "$(_fdbinpath)" dev --config "$(_fdconfig)" "$@"; return; fi
    _fd_dispatch "$1" sudo "$(_fdbinpath)" dev --config "$(_fdconfig)"
}
function testnetfd() {
    if [ "$1" = gdb ]; then shift; sudo gdb -q --args "$(_fdbinpath)" --testnet --config "$(_fdconfig)" "$@"; return; fi
    _fd_dispatch "$1" sudo "$(_fdbinpath)" --testnet --config "$(_fdconfig)"
}
function flamefd()   { _fd_dispatch "$1" sudo "$(_fdbinpath)" flame --config "$(_fdconfig)"; }    # perf flamegraph
function metricsfd() { _fd_dispatch "$1" sudo "$(_fdbinpath)" metrics --config "$(_fdconfig)"; }  # Prometheus metrics
function memfd() {
    if [ "$1" = cmd ]; then _fd_show sudo "$(_fdbinpath)" mem --config "$(_fdconfig)"; return; fi
    sudo "$(_fdbinpath)" mem --config "$(_fdconfig)" | less
}
function initfd()    { _fd_dispatch "$1" sudo "$(_fdbinpath)" configure init all --config "$(_fdconfig)"; }
function finifd()    { _fd_dispatch "$1" sudo "$(_fdbinpath)" configure fini all --config "$(_fdconfig)"; }

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
