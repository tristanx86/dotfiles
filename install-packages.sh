# Package lists shared between install.sh and wipe.sh — single source of
# truth so wipedot's "what did dotfiles actually install" tracking can't
# drift out of sync with what install.sh actually installs.

DEBIAN_PKGS=(build-essential git zsh curl wget unzip tar
             xclip nodejs npm ripgrep fd-find python3-venv
             cmake clang lldb lld cppcheck pkg-config libssl-dev
             tmux gdb zoxide htop btop numactl)
DEBIAN_PERF_PKGS=(linux-tools-common linux-tools-generic bpftrace bpfcc-tools trace-cmd sysstat)
DEBIAN_NEOVIM_PKGS=(neovim)

RHEL_PKGS=(gcc gcc-c++ make git zsh curl wget unzip tar
           xclip nodejs npm ripgrep fd-find python3 python3-pip
           cmake clang lldb lld cppcheck pkgconf-pkg-config openssl-devel
           tmux gdb zoxide htop btop numactl)
RHEL_EXTRA_PKGS=(kitty-terminfo)
RHEL_PERF_PKGS=(perf bpftrace bcc-tools trace-cmd sysstat)
RHEL_NEOVIM_PKGS=(neovim)

BREW_FORMULAE=(git zsh wget node ripgrep fd neovim cmake llvm cppcheck rustup-init tmux gdb zoxide htop btop)
BREW_CASKS=(kitty font-fira-code-nerd-font)
# Symbols-only Nerd Font: kitty uses it as a glyph fallback so all NF icons
# render correctly regardless of which codepoints FiraCode patches in. Kept
# separate (not required) since its install is allowed to fail silently.
BREW_CASKS_SOFT=(font-symbols-only-nerd-font)

# wipedot NEVER auto-removes these, no matter what the preexisting-snapshot
# diff says — removing any of them risks breaking the machine itself, not
# just dotfiles' setup:
#   python3/python3-pip/python3-venv: dnf/yum are themselves Python-based on
#     RHEL/Fedora — removing python3 there can cascade into removing dnf's
#     own dependencies and leave the box unable to install/remove anything.
#   zsh: likely your active login shell over SSH; removing the binary out
#     from under a login shell risks locking you out.
#   git/curl/wget/tar/unzip: foundational utilities other tooling silently
#     assumes exist, and exactly what you'd need to recover the box if
#     anything else here goes wrong.
#   build-essential/gcc/gcc-c++/make: commonly a load-bearing dependency for
#     other software's install-time native compilation.
# Worst case with this list: a few packages dotfiles installed are left
# behind after wipedot. That's the acceptable failure direction — the
# alternative (auto-removing one of these) is not.
PKGS_NEVER_REMOVE=(python3 python3-pip python3-venv git curl wget tar unzip zsh build-essential gcc gcc-c++ make)
