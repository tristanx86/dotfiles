#!/usr/bin/env bash
# Minimal install for a machine that only needs `floodsd` ("flood standalone")
# — the standalone remote load-generator. Installs nothing else: no themes,
# oh-my-zsh, nvim config, tmux config, kitty/iterm2 config, or shell rc
# changes. Safe to hand to someone else's box.
#
# `floodsd` is a deliberately different name from `floodfd` (the zsh function
# in zsh/firedancer-flood.zsh, used by the full dotfiles install) so the two
# can coexist on the same machine without colliding — same behavior, separate
# binary/state/temp files, no zsh dependency, works from bash or zsh on any
# distro.
#
# What this does:
#   - Copies bin/floodsd (a single self-contained bash script) to
#     /usr/local/bin (via sudo, so it's on PATH immediately for everyone —
#     no shell restart, no PATH edits). Falls back to ~/.local/bin if sudo
#     isn't available.
#
# That's the whole install. DPDK/Pktgen-DPDK, if you use `floodsd dpdk`, is
# installed lazily on first run with its own confirmation prompt — this
# script never touches packages.
#
# Run on the server:  bash install-floodsd.sh

set -uo pipefail
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="$DOTFILES_DIR/bin/floodsd"

if [ ! -f "$SRC" ]; then
    echo "[ERROR] $SRC not found — is this script running from inside a clone of the dotfiles repo?"
    exit 1
fi

_install_user_local() {
    local dest_dir="$HOME/.local/bin"
    mkdir -p "$dest_dir"
    cp "$SRC" "$dest_dir/floodsd"
    chmod +x "$dest_dir/floodsd"
    echo "[floodsd] Installed to $dest_dir/floodsd."
    case ":$PATH:" in
        *":$dest_dir:"*) echo "[floodsd] $dest_dir is on your PATH — run: floodsd setup" ;;
        *) echo "[floodsd] $dest_dir isn't on your PATH — run it directly: $dest_dir/floodsd setup" ;;
    esac
}

# /usr/local/bin is on PATH by default on essentially every Linux distro and
# macOS, for every user, with no relogin needed — floodsd already requires
# sudo for every real operation (NIC binds, pktgen, hugepages), so asking for
# it once here at install time isn't an extra burden.
if sudo -v 2>/dev/null && sudo install -m 755 "$SRC" /usr/local/bin/floodsd 2>/dev/null; then
    echo "[floodsd] Installed to /usr/local/bin/floodsd — run: floodsd setup"
else
    echo "[floodsd] Couldn't install to /usr/local/bin (no sudo, or install failed) — falling back to ~/.local/bin."
    _install_user_local
fi
