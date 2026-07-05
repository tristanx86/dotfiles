#!/usr/bin/env bash
# wipedot: undo what install.sh did. Meant for fresh machines/servers where
# install.sh has been recording an original-state snapshot since its very
# first run (see install.sh's "Original-state snapshot" section) — that
# snapshot is what lets us tell "dotfiles installed this" (safe to remove)
# apart from "this was already here" (never touch it).
#
# Guiding rule: under-delete, never over-delete. Every removal below is
# gated on either (a) the path/name being exclusively dotfiles' regardless of
# history (e.g. ~/.config/dotfiles), or (b) a snapshot explicitly confirming
# it wasn't there before dotfiles ran. Anything we can't be sure about is
# left in place and reported, never guessed-and-removed. Certain foundational
# packages (python3, zsh, git, curl/wget, gcc/make — see PKGS_NEVER_REMOVE in
# install-packages.sh) are never auto-removed at all, full stop, regardless
# of the snapshot, because removing them risks breaking the machine itself
# (e.g. python3 underpins dnf/yum on RHEL/Fedora).
#
# On a machine where dotfiles was already set up *before* the snapshot
# feature existed, there's nothing to diff against — we degrade gracefully:
# unlink symlinks (restoring backups) and remove exclusively-dotfiles paths,
# leave everything else untouched, and just offer to delete the dotfiles
# folder itself.
set -uo pipefail

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS="$(uname -s)"
STATE_DIR="$HOME/.cache/dotfiles"
ORIGINAL_STATE_FILE="$STATE_DIR/original-state"
source "$DOTFILES_DIR/install-packages.sh"

echo "==== wipedot ===="
echo "This removes dotfiles-managed symlinks and exclusively-dotfiles state"
echo "from this machine. With an original-state snapshot (see install.sh), it"
echo "also offers to remove packages/tools/prefs confirmed to predate dotfiles"
echo "as absent, and revert your login shell — each behind its own prompt."
read -p "Continue? [y/N] " ans
case "$ans" in y|Y|yes|Yes) ;; *) echo "Aborted."; exit 1 ;; esac

# Read the snapshot now, before anything below could remove $STATE_DIR (where
# it lives) — otherwise we'd always see "no snapshot" regardless of whether
# one existed. $STATE_DIR itself is removed at the very end, once done with it.
HAVE_SNAPSHOT=0
if [ -f "$ORIGINAL_STATE_FILE" ]; then
    HAVE_SNAPSHOT=1
    source "$ORIGINAL_STATE_FILE"
fi

# -----------------------------------------------------------------------------
# Always safe: symlinks (self-contained — only unlinks paths actually
# pointing into $DOTFILES_DIR, restores the earliest backup found) and paths
# that are exclusively dotfiles' by construction (the name/location can't
# collide with anything a user would have independently), regardless of
# snapshot or history.
# -----------------------------------------------------------------------------

# _oldest_backup <dest>: find the earliest create_symlink backup for <dest>
# (named "<dest>.backup.<epoch>") — the earliest one is the closest thing to
# the file's actual pre-dotfiles state.
_oldest_backup() {
    local dest=$1 f ts oldest="" oldest_ts=""
    for f in "$dest".backup.*; do
        [ -e "$f" ] || continue
        ts="${f#"$dest".backup.}"
        if [ -z "$oldest" ] || [ "$ts" -lt "$oldest_ts" ]; then
            oldest="$f"; oldest_ts="$ts"
        fi
    done
    [ -n "$oldest" ] && echo "$oldest"
}

_unlink_if_ours() {
    local dest=$1
    [ -L "$dest" ] || return 0
    case "$(readlink "$dest")" in
        "$DOTFILES_DIR"/*) ;;
        *) return 0 ;;
    esac
    rm -f "$dest"
    echo "[Unlink] $dest"
    local backup
    backup="$(_oldest_backup "$dest")"
    if [ -n "$backup" ]; then
        mv "$backup" "$dest"
        echo "[Restore] $backup -> $dest"
    fi
}

echo "==== Removing symlinks (restoring pre-dotfiles backups where found) ===="
for f in "$HOME/.zshrc" "$HOME/.p10k.zsh" "$HOME/.bashrc" "$HOME/.bash_profile" \
         "$HOME/.tmux.conf" "$HOME/.config/kitty/kitty.conf" "$HOME/.config/nvim"; do
    _unlink_if_ours "$f"
done

echo "==== Removing exclusively-dotfiles state ===="
rm -rf "$HOME/.config/dotfiles" \
       /tmp/pktfd-bound /tmp/pktfd-setup.pkt /tmp/floodfd-bound /tmp/floodfd-dpdk.pkt
if [[ "$OS" == "Darwin" ]]; then
    rm -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/TokyoNight.json"
fi

# -----------------------------------------------------------------------------
# Snapshot-gated: everything below is only removed if the snapshot explicitly
# confirms it wasn't there before dotfiles ran. Without a snapshot, all of it
# is left in place — we'd rather leave dotfiles-installed leftovers behind
# than risk deleting something that predates dotfiles and was never ours.
# -----------------------------------------------------------------------------
if [ "$HAVE_SNAPSHOT" -eq 0 ]; then
    echo
    echo "[wipedot] No original-state snapshot found — this machine's dotfiles"
    echo "  install predates wipedot (or a snapshot was never recorded), so I"
    echo "  can't tell what existed before dotfiles ran. Leaving in place, untouched:"
    echo "    Oh-My-Zsh, Powerlevel10k, Rust/cargo, Kitty, Nerd Font, tree-sitter-cli,"
    echo "    tmux plugins, Neovim plugin data, packages, login shell, iTerm2 prefs."
    read -p "Remove the dotfiles folder itself ($DOTFILES_DIR)? [y/N] " ans
    case "$ans" in
        y|Y|yes|Yes) rm -rf "$DOTFILES_DIR"; echo "[Removed] $DOTFILES_DIR" ;;
        *) echo "Left $DOTFILES_DIR in place." ;;
    esac
    rm -rf "$STATE_DIR"
    echo "==== wipedot: done (partial — no snapshot) ===="
    exit 0
fi

echo
echo "==== Oh-My-Zsh, Rust, Kitty, fonts, tmux plugins, Neovim data ===="
NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

if [ "${PREEXISTING_OHMYZSH:-0}" -eq 0 ]; then
    rm -rf "$HOME/.oh-my-zsh" && echo "[Removed] ~/.oh-my-zsh"
else
    echo "[Left in place] ~/.oh-my-zsh (predates dotfiles)"
    # p10k lives inside oh-my-zsh's tree — if oh-my-zsh itself predates
    # dotfiles but p10k was added fresh by dotfiles, remove just that subdir.
    if [ "${PREEXISTING_P10K:-0}" -eq 0 ]; then
        rm -rf "$P10K_DIR" && echo "[Removed] $P10K_DIR"
    else
        echo "[Left in place] $P10K_DIR (predates dotfiles)"
    fi
fi

if [ "${PREEXISTING_CARGO:-0}" -eq 0 ]; then
    rm -rf "$HOME/.cargo" "$HOME/.rustup" && echo "[Removed] ~/.cargo ~/.rustup"
else
    echo "[Left in place] ~/.cargo ~/.rustup (Rust predates dotfiles)"
fi

if [ "${PREEXISTING_KITTY:-0}" -eq 0 ]; then
    rm -rf "$HOME/.local/kitty.app" "$HOME/.local/bin/kitty" && echo "[Removed] Kitty"
else
    echo "[Left in place] Kitty (predates dotfiles)"
fi

if [ "${PREEXISTING_FONT:-0}" -eq 0 ]; then
    rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/FiraCode" && echo "[Removed] FiraCode Nerd Font"
else
    echo "[Left in place] FiraCode Nerd Font (predates dotfiles)"
fi

if [ "${PREEXISTING_TREESITTER_CLI:-0}" -eq 0 ] && command -v tree-sitter >/dev/null 2>&1; then
    npm uninstall -g tree-sitter-cli 2>/dev/null || sudo npm uninstall -g tree-sitter-cli 2>/dev/null
    echo "[Removed] tree-sitter-cli"
elif [ "${PREEXISTING_TREESITTER_CLI:-0}" -eq 1 ]; then
    echo "[Left in place] tree-sitter-cli (predates dotfiles)"
fi

if [ "${PREEXISTING_TPM:-0}" -eq 0 ]; then
    rm -rf "$HOME/.tmux/plugins" && echo "[Removed] ~/.tmux/plugins"
else
    echo "[Left in place] ~/.tmux/plugins (predates dotfiles)"
fi

if [ "${PREEXISTING_NVIM_DATA:-0}" -eq 0 ]; then
    rm -rf "$NVIM_DATA_DIR" && echo "[Removed] $NVIM_DATA_DIR"
else
    echo "[Left in place] $NVIM_DATA_DIR (predates dotfiles — can't safely tell dotfiles'"
    echo "  plugin data apart from anything else that was already in there)"
fi

if [[ "$OS" == "Darwin" ]]; then
    echo
    echo "==== iTerm2 prefs ===="
    if [ "${ITERM_GUID_WAS_SET:-0}" -eq 1 ]; then
        defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "${ORIGINAL_ITERM_GUID:-}"
        echo "[Restored] Default Bookmark Guid -> ${ORIGINAL_ITERM_GUID:-}"
    else
        defaults delete com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true
        echo "[Removed] Default Bookmark Guid override"
    fi
    if [ "${ITERM_CLIP_WAS_SET:-0}" -eq 1 ]; then
        defaults write com.googlecode.iterm2 AllowClipboardAccess -bool "${ORIGINAL_ITERM_CLIP:-}"
        echo "[Restored] AllowClipboardAccess -> ${ORIGINAL_ITERM_CLIP:-}"
    else
        defaults delete com.googlecode.iterm2 AllowClipboardAccess 2>/dev/null || true
        echo "[Removed] AllowClipboardAccess override"
    fi
fi

# Recompute distro family fresh (same machine, same logic as install.sh).
DISTRO_FAMILY="" RHEL_PKG=""
if [[ "$OS" == "Linux" ]]; then
    if command -v apt-get &>/dev/null; then
        DISTRO_FAMILY="debian"
    elif command -v dnf &>/dev/null; then
        DISTRO_FAMILY="rhel"; RHEL_PKG="dnf"
    elif command -v yum &>/dev/null; then
        DISTRO_FAMILY="rhel"; RHEL_PKG="yum"
    fi
fi

_not_preexisting() {
    local pkg=$1 p
    for p in $PREEXISTING_PKGS; do [ "$p" = "$pkg" ] && return 1; done
    return 0
}
_never_remove() {
    local pkg=$1 p
    for p in "${PKGS_NEVER_REMOVE[@]+"${PKGS_NEVER_REMOVE[@]}"}"; do [ "$p" = "$pkg" ] && return 0; done
    return 1
}

echo
echo "==== Packages installed by dotfiles ===="
to_remove=() protected_skipped=()
case "$DISTRO_FAMILY" in
    debian)
        for pkg in "${DEBIAN_PKGS[@]+"${DEBIAN_PKGS[@]}"}" "${DEBIAN_PERF_PKGS[@]+"${DEBIAN_PERF_PKGS[@]}"}" "${DEBIAN_NEOVIM_PKGS[@]+"${DEBIAN_NEOVIM_PKGS[@]}"}"; do
            _not_preexisting "$pkg" || continue
            if _never_remove "$pkg"; then protected_skipped+=("$pkg"); else to_remove+=("$pkg"); fi
        done
        ;;
    rhel)
        for pkg in "${RHEL_PKGS[@]+"${RHEL_PKGS[@]}"}" "${RHEL_EXTRA_PKGS[@]+"${RHEL_EXTRA_PKGS[@]}"}" "${RHEL_PERF_PKGS[@]+"${RHEL_PERF_PKGS[@]}"}" "${RHEL_NEOVIM_PKGS[@]+"${RHEL_NEOVIM_PKGS[@]}"}"; do
            _not_preexisting "$pkg" || continue
            if _never_remove "$pkg"; then protected_skipped+=("$pkg"); else to_remove+=("$pkg"); fi
        done
        ;;
esac
brew_formulae_remove=() brew_casks_remove=()
if [[ "$OS" == "Darwin" ]]; then
    for pkg in "${BREW_FORMULAE[@]+"${BREW_FORMULAE[@]}"}"; do
        _not_preexisting "$pkg" || continue
        if _never_remove "$pkg"; then protected_skipped+=("$pkg"); else brew_formulae_remove+=("$pkg"); fi
    done
    for pkg in "${BREW_CASKS[@]+"${BREW_CASKS[@]}"}" "${BREW_CASKS_SOFT[@]+"${BREW_CASKS_SOFT[@]}"}"; do
        _not_preexisting "$pkg" && brew_casks_remove+=("$pkg")
    done
fi

if [ "${#protected_skipped[@]}" -gt 0 ]; then
    echo "Never auto-removed regardless of snapshot (see PKGS_NEVER_REMOVE) — left in place:"
    printf '  %s\n' "${protected_skipped[@]}"
fi

if [ "${#to_remove[@]}" -eq 0 ] && [ "${#brew_formulae_remove[@]}" -eq 0 ] && [ "${#brew_casks_remove[@]}" -eq 0 ]; then
    echo "Nothing else to remove."
else
    echo "These were NOT present before dotfiles first ran, so dotfiles installed them:"
    printf '  %s\n' "${to_remove[@]+"${to_remove[@]}"}" \
                     "${brew_formulae_remove[@]+"${brew_formulae_remove[@]}"}" \
                     "${brew_casks_remove[@]+"${brew_casks_remove[@]}"}"
    echo
    echo "Removing shared packages can affect other software on this machine"
    echo "if anything else came to depend on them after the fact."
    read -p "Remove these packages? [y/N] " ans
    case "$ans" in
        y|Y|yes|Yes)
            case "$DISTRO_FAMILY" in
                debian) [ "${#to_remove[@]}" -gt 0 ] && sudo apt-get remove -y "${to_remove[@]}" ;;
                rhel)   [ "${#to_remove[@]}" -gt 0 ] && sudo "$RHEL_PKG" remove -y "${to_remove[@]}" ;;
            esac
            [ "${#brew_formulae_remove[@]}" -gt 0 ] && brew uninstall "${brew_formulae_remove[@]}"
            [ "${#brew_casks_remove[@]}" -gt 0 ] && brew uninstall --cask "${brew_casks_remove[@]}"
            ;;
        *) echo "Left packages in place." ;;
    esac
fi

echo
echo "==== Login shell ===="
CUR_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
[ -z "$CUR_SHELL" ] && CUR_SHELL="$SHELL"
if [ -n "${ORIGINAL_SHELL:-}" ] && [ -x "$ORIGINAL_SHELL" ] && [ "$CUR_SHELL" != "$ORIGINAL_SHELL" ]; then
    read -p "Revert login shell from $CUR_SHELL back to $ORIGINAL_SHELL? [y/N] " ans
    case "$ans" in
        y|Y|yes|Yes)
            if chsh -s "$ORIGINAL_SHELL" "$USER" 2>/dev/null || sudo chsh -s "$ORIGINAL_SHELL" "$USER" 2>/dev/null; then
                echo "[Shell] Login shell reverted to $ORIGINAL_SHELL."
            else
                echo "[WARNING] chsh failed — revert manually if needed."
            fi
            ;;
        *) echo "Left login shell as $CUR_SHELL." ;;
    esac
elif [ -n "${ORIGINAL_SHELL:-}" ] && [ ! -x "$ORIGINAL_SHELL" ]; then
    echo "Recorded original shell ($ORIGINAL_SHELL) no longer exists on this machine — leaving login shell as $CUR_SHELL."
else
    echo "Login shell already matches the original — nothing to revert."
fi

read -p "Remove the dotfiles folder itself ($DOTFILES_DIR)? [y/N] " ans
case "$ans" in
    y|Y|yes|Yes) rm -rf "$DOTFILES_DIR"; echo "[Removed] $DOTFILES_DIR" ;;
    *) echo "Left $DOTFILES_DIR in place." ;;
esac

rm -rf "$STATE_DIR"
echo "==== wipedot: done ===="
