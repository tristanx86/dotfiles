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
#     ~/.local/bin — never system-wide. This typically runs on someone
#     else's server (you have sudo, but it's their box), so nothing gets
#     installed outside your own user dir except the specific kernel/NIC
#     operations (vfio-pci bind, hugepages, pktgen module) that floodsd
#     itself needs sudo for at runtime — those are unavoidably system state,
#     not files left behind.
#
# That's the whole install. DPDK/Pktgen-DPDK, if you use `floodsd dpdk`, is
# installed lazily on first run with its own confirmation prompt. DPDK's own
# dev packages come from the system package manager (no user-dir equivalent
# without rebuilding DPDK from source), but Pktgen-DPDK itself is built and
# installed into ~/.local — this script never touches /usr/local or system
# package state up front.
#
# Run on the server:  bash install-floodsd.sh

set -uo pipefail
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="$DOTFILES_DIR/bin/floodsd"

if [ ! -f "$SRC" ]; then
    echo "[ERROR] $SRC not found — is this script running from inside a clone of the dotfiles repo?"
    exit 1
fi

dest_dir="$HOME/.local/bin"
mkdir -p "$dest_dir"
cp "$SRC" "$dest_dir/floodsd"
chmod +x "$dest_dir/floodsd"
echo "[floodsd] Installed to $dest_dir/floodsd."
case ":$PATH:" in
    *":$dest_dir:"*) echo "[floodsd] $dest_dir is on your PATH — run: floodsd setup" ;;
    *) echo "[floodsd] $dest_dir isn't on your PATH — run it directly: $dest_dir/floodsd setup" ;;
esac
