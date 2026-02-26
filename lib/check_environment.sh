#!/usr/bin/env bash
# lib/check_environment.sh — Pre-flight environment checks for open-chad
#
# Verifies:
#   1. Ubuntu/Debian-based OS (required for apt-get bootstrap)
#   2. git is present in PATH (required for update command)
#   3. Available disk space >= 500MB (needed for toolchain installs)
#   4. No conflicting installations that would break the install
#
# Exit codes:
#   0  — All checks passed
#   1  — One or more checks failed (actionable error messages printed to stderr)
#
# Environment overrides:
#   OPEN_CHAD_MIN_DISK_MB  — Minimum disk space in MB (default: 500)
#
# Called by install.sh before wizard.sh and by update.sh before git pull.

set -uo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

check()  { echo -e "${C_GOLD}[env]${C_RESET} Checking: $*"; }
ok()     { echo -e "${C_SAGE}[env] OK:${C_RESET} $*"; }
warn()   { echo -e "${C_GOLD}[env] WARN:${C_RESET} $*"; }
error()  { echo -e "${C_CORAL}[env] ERROR:${C_RESET} $*" >&2; }
hint()   { echo -e "${C_CORAL}       ↳${C_RESET} $*" >&2; }

FAILED=0
OPEN_CHAD_MIN_DISK_MB="${OPEN_CHAD_MIN_DISK_MB:-500}"

# ─── 1. OS check — Ubuntu/Debian only ────────────────────────────────────────
check "OS distribution (Ubuntu/Debian required)"

_os_ok=0

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian)
            _os_ok=1
            ok "OS: ${PRETTY_NAME:-$ID}"
            ;;
        *)
            # Check ID_LIKE for derivatives (LinuxMint, Pop!_OS, etc.)
            case "${ID_LIKE:-}" in
                *ubuntu*|*debian*)
                    _os_ok=1
                    ok "OS: ${PRETTY_NAME:-$ID} (Ubuntu/Debian derivative)"
                    ;;
            esac
            ;;
    esac
fi

if [ "$_os_ok" -eq 0 ]; then
    error "Unsupported OS. open-chad requires Ubuntu 22.04+ or Debian 12+."
    hint "Detected: ${PRETTY_NAME:-unknown}"
    hint "The apt-get dependency bootstrap will not work on other distributions."
    hint "macOS/Arch/Fedora support is not planned — see README for manual install."
    FAILED=$((FAILED + 1))
fi

# ─── 2. git presence check ────────────────────────────────────────────────────
check "git (required for open-chad update)"

if command -v git &>/dev/null; then
    _git_version=$(git --version 2>/dev/null | awk '{print $3}')
    ok "git ${_git_version}"
else
    error "git not found in PATH."
    hint "Install git:  sudo apt-get install -y git"
    hint "git is required by the 'open-chad update' command."
    FAILED=$((FAILED + 1))
fi

# ─── 3. Disk space check — 500MB minimum ─────────────────────────────────────
check "Available disk space (>= ${OPEN_CHAD_MIN_DISK_MB}MB on \$HOME filesystem)"

# df -P gives POSIX output: filesystem, 1K-blocks, Used, Available, Use%, Mounted
_avail_kb=""
if ! _avail_kb=$(df -P "$HOME" 2>/dev/null | awk 'NR==2 {print $4}') || [ -z "$_avail_kb" ]; then
    error "Could not determine available disk space (df failed on \$HOME)."
    hint "Check that \$HOME ($HOME) is a valid mounted filesystem."
    hint "You can skip this check with: --no-env-check"
    FAILED=$((FAILED + 1))
else
    _avail_mb=$(( _avail_kb / 1024 ))
    if [ "$_avail_mb" -ge "$OPEN_CHAD_MIN_DISK_MB" ]; then
        ok "Disk space: ${_avail_mb}MB available (minimum: ${OPEN_CHAD_MIN_DISK_MB}MB)"
    else
        error "Insufficient disk space: ${_avail_mb}MB available, ${OPEN_CHAD_MIN_DISK_MB}MB required."
        hint "Free up space, then re-run install.sh."
        hint "Toolchains (uv, rust, go) need ~${OPEN_CHAD_MIN_DISK_MB}MB to download and install."
        FAILED=$((FAILED + 1))
    fi
fi

# ─── 3b. python3 check (required for session title SQLite query) ─────────────
check "python3 (required for session title lookup)"

if command -v python3 &>/dev/null; then
    _py_version=$(python3 --version 2>/dev/null | awk '{print $2}')
    ok "python3 ${_py_version:-installed}"
else
    warn "python3 not found in PATH. Session titles may be empty in tmux."
    hint "Install python3:  sudo apt-get install -y python3"
fi

# ─── 4. Conflicting installation check ───────────────────────────────────────
check "Conflicting installations"

_conflicts=0

# Check if open-chad is already installed via a package manager (would conflict with symlink)
if command -v open-chad &>/dev/null; then
    _oc_path=$(command -v open-chad)
    # It's OK if the existing install is a symlink (idempotent reinstall)
    if [ ! -L "$_oc_path" ]; then
        error "open-chad found at $_oc_path but it is not a symlink."
        hint "This may be a conflicting system installation."
        hint "Remove it or check PATH ordering before continuing."
        _conflicts=$((_conflicts + 1))
    else
        ok "Existing open-chad symlink at $_oc_path (idempotent reinstall)"
    fi
fi

# Auto-fix if $HOME/.local/bin is not in PATH (install won't be usable without it)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${C_GOLD}[env] WARN:${C_RESET} \$HOME/.local/bin is not in \$PATH — auto-fixing shell profile..."
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "$_SCRIPT_DIR/setup_shell_profile.sh" || \
        echo -e "       ${C_CORAL}↳${C_RESET} Could not auto-fix. Add manually:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

if [ "$_conflicts" -eq 0 ]; then
    ok "No conflicting installations found"
else
    FAILED=$((FAILED + _conflicts))
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
if [ "$FAILED" -gt 0 ]; then
    echo -e "" >&2
    error "$FAILED pre-flight check(s) failed. Resolve the issues above and re-run install.sh."
    exit 1
fi

ok "All pre-flight checks passed."
