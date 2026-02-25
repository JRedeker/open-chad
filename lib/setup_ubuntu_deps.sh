#!/usr/bin/env bash
# lib/setup_ubuntu_deps.sh — Silent apt dependency bootstrap for Ubuntu/Debian
#
# Installs core system tools required for open-chad and optional language
# toolchain prerequisites. All output is redirected to log file; only errors
# surface to the terminal.
#
# Core packages always installed:
#   git, curl, tmux, build-essential, nodejs, npm, pnpm (via npm)
#
# Optional packages (installed only when bundles are selected):
#   python3, python3-pip, python3-venv  — Python bundle prerequisite
#   golang-go                           — Go bundle (via apt; updated via tarball if stale)
#   (Rust uses rustup, no apt package)
#
# Environment overrides:
#   OPEN_CHAD_INSTALL_LOG   — log file path (default: /tmp/open-chad-install.log)
#   OPEN_CHAD_BUNDLES       — space-separated bundle names: "python go rust"
#   DEBIAN_FRONTEND         — set externally or defaults to noninteractive here
#
# Exit codes:
#   0  — All required packages installed
#   1  — apt-get failure (error + recovery steps printed to stderr)
#
# Called by wizard.sh and install.sh --yes. Safe to call standalone.

set -uo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[deps]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[deps] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[deps] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[deps] ERROR:${C_RESET} $*" >&2; }
hint()  { echo -e "${C_CORAL}       ↳${C_RESET} $*" >&2; }

# ─── Configuration ────────────────────────────────────────────────────────────
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"
BUNDLES="${OPEN_CHAD_BUNDLES:-}"
export DEBIAN_FRONTEND=noninteractive

# Initialize log file with timestamp header
{
    echo "=== open-chad apt bootstrap $(date -Iseconds) ==="
    echo "BUNDLES: ${BUNDLES:-none}"
} >> "$INSTALL_LOG"

# ─── apt-get failure handler ──────────────────────────────────────────────────
_apt_failed() {
    local pkg="$1"
    local exit_code="$2"
    error "apt-get failed while installing: ${pkg} (exit code: ${exit_code})"
    hint "Log file: $INSTALL_LOG"
    hint ""
    hint "Recovery steps:"
    hint "  1. Check disk space:   df -h ~"
    hint "  2. Check network:      curl -I https://archive.ubuntu.com"
    hint "  3. Refresh apt cache:  sudo apt-get update"
    hint "  4. Install manually:   sudo apt-get install -y ${pkg}"
    hint "  5. Re-run installer:   bash install.sh"
    echo "" >> "$INSTALL_LOG"
    echo "FAILED: $pkg (exit $exit_code)" >> "$INSTALL_LOG"
    exit 1
}

# ─── Sudo check ───────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ] && ! command -v sudo &>/dev/null; then
    error "This script requires root or sudo access to install packages."
    hint "Run as root or install sudo first."
    exit 1
fi

_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    _SUDO="sudo"
fi

# ─── Silent apt runner (uses $_SUDO when not root) ───────────────────────────
_apt_install() {
    local pkg_list=("$@")
    local pkg_str="${pkg_list[*]}"
    step "Installing: $pkg_str"
    echo "[$(date -Iseconds)] apt-get install: $pkg_str" >> "$INSTALL_LOG"

    local exit_code=0
    DEBIAN_FRONTEND=noninteractive $_SUDO apt-get install -qq -y --no-install-recommends \
        "${pkg_list[@]}" >> "$INSTALL_LOG" 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        _apt_failed "$pkg_str" "$exit_code"
    fi
    ok "Installed: $pkg_str"
}

# ─── 1. apt-get update ────────────────────────────────────────────────────────
step "Refreshing apt package cache"
echo "[$(date -Iseconds)] apt-get update" >> "$INSTALL_LOG"
local_exit=0
DEBIAN_FRONTEND=noninteractive $_SUDO apt-get update -qq >> "$INSTALL_LOG" 2>&1 || local_exit=$?
if [ "$local_exit" -ne 0 ]; then
    warn "apt-get update returned non-zero (exit $local_exit). Continuing anyway."
    warn "Some packages may be outdated. Check $INSTALL_LOG for details."
fi
ok "apt cache refreshed"

# ─── 2. Core packages ────────────────────────────────────────────────────────
# Always installed regardless of bundle selection
_apt_install git curl wget ca-certificates tmux build-essential

# Node.js: prefer system node if >= 18, otherwise install via NodeSource
_node_ver=0
if command -v node &>/dev/null; then
    _node_ver=$(node --version 2>/dev/null | sed 's/v\([0-9]*\).*/\1/' || echo 0)
fi

if [ "$_node_ver" -ge 18 ]; then
    ok "node $(node --version) already installed (>= 18)"
else
    step "Installing Node.js 20 LTS via NodeSource"
    echo "[$(date -Iseconds)] NodeSource Node.js 20 install" >> "$INSTALL_LOG"
    {
        curl -fsSL https://deb.nodesource.com/setup_20.x | $_SUDO bash -
    } >> "$INSTALL_LOG" 2>&1 || {
        warn "NodeSource setup failed — falling back to distro nodejs"
        _apt_install nodejs npm
    }
    _apt_install nodejs
    ok "node $(node --version 2>/dev/null || echo 'unknown') installed"
fi

# npm (may already be bundled with nodejs)
if ! command -v npm &>/dev/null; then
    _apt_install npm
fi

# pnpm (required for ADV and morph plugins)
if ! command -v pnpm &>/dev/null; then
    step "Installing pnpm via npm"
    echo "[$(date -Iseconds)] npm install -g pnpm" >> "$INSTALL_LOG"
    local_exit=0
    $_SUDO npm install -g pnpm >> "$INSTALL_LOG" 2>&1 || local_exit=$?
    if [ "$local_exit" -ne 0 ]; then
        warn "pnpm global install failed (exit $local_exit). ADV and morph setup may fail."
        warn "Fix manually: sudo npm install -g pnpm"
    else
        ok "pnpm installed"
    fi
else
    ok "pnpm already installed ($(pnpm --version 2>/dev/null || echo 'unknown'))"
fi

# ─── 3. Bundle-specific packages ──────────────────────────────────────────────

if [[ " $BUNDLES " == *" python "* ]]; then
    step "Installing Python bundle prerequisites"
    # uv manages Python versions itself; we only need curl (already installed)
    # and pip/venv for any system-level tools that pre-date uv
    _apt_install python3-pip python3-venv
    ok "Python apt prerequisites installed (uv manages Python versions)"
fi

if [[ " $BUNDLES " == *" go "* ]]; then
    step "Installing Go bundle prerequisites"
    # golang-go from apt may be outdated; setup_dev_bundle.sh will upgrade if needed
    _apt_install golang-go
    ok "Go apt package installed (setup_dev_bundle.sh may upgrade to latest)"
fi

# Rust uses rustup (no apt package) — no apt installs needed
if [[ " $BUNDLES " == *" rust "* ]]; then
    # Ensure curl is present (already installed above)
    ok "Rust bundle: no apt packages required (rustup handles install)"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo "[$(date -Iseconds)] apt bootstrap complete" >> "$INSTALL_LOG"
ok "apt dependency bootstrap complete. Log: $INSTALL_LOG"
