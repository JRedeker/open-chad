#!/usr/bin/env bash
# lib/setup_omp.sh — Install/update opencode-model-preferences (omp)
#
# Actions:
#   1. Clone or pull the omp repo to ~/dev/oc-plugins/opencode-model-preferences/
#   2. Run go build to produce the omp binary
#   3. Install the binary to ~/.local/bin/omp
#
# Environment overrides:
#   OMP_REPO         — git URL (default: https://github.com/JRedeker/opencode-model-preferences.git)
#   OMP_CHECKOUT_DIR — local path (default: ~/dev/oc-plugins/opencode-model-preferences)
#   OMP_INSTALL_DIR  — binary destination (default: ~/.local/bin)
#
# Called by install.sh and update.sh. Safe to call standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors (match install.sh palette) ───────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[omp]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[omp] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[omp] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[omp] ERROR:${C_RESET} $*" >&2; }

# ─── Configuration ────────────────────────────────────────────────────────────
OMP_REPO="${OMP_REPO:-https://github.com/JRedeker/opencode-model-preferences.git}"
OMP_CHECKOUT_DIR="${OMP_CHECKOUT_DIR:-$HOME/dev/oc-plugins/opencode-model-preferences}"
OMP_INSTALL_DIR="${OMP_INSTALL_DIR:-$HOME/.local/bin}"

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v go &>/dev/null; then
    warn "go not found in PATH. Skipping omp install."
    warn "To install omp later, install Go 1.16+ and re-run:"
    warn "  bash $REPO_DIR/lib/setup_omp.sh"
    exit 0
fi

# ─── Git clone or pull ────────────────────────────────────────────────────────
if [ -d "$OMP_CHECKOUT_DIR/.git" ]; then
    step "Updating omp at $OMP_CHECKOUT_DIR"
    if ! git -C "$OMP_CHECKOUT_DIR" pull --no-edit --quiet 2>/dev/null; then
        warn "git pull failed — checkout may have local changes or be diverged."
        warn "Resolve manually: cd $OMP_CHECKOUT_DIR && git status"
        warn "Continuing with existing checkout."
    fi
elif [ -d "$OMP_CHECKOUT_DIR" ]; then
    # Directory exists but is not a git repo — quarantine it
    local_bak="$OMP_CHECKOUT_DIR.bak.$(date +%s)"
    warn "Directory exists but is not a git repo: $OMP_CHECKOUT_DIR"
    warn "Quarantining to: $local_bak"
    mv "$OMP_CHECKOUT_DIR" "$local_bak"
    step "Cloning omp from $OMP_REPO -> $OMP_CHECKOUT_DIR"
    mkdir -p "$(dirname "$OMP_CHECKOUT_DIR")"
    git clone "$OMP_REPO" "$OMP_CHECKOUT_DIR"
else
    step "Cloning omp from $OMP_REPO -> $OMP_CHECKOUT_DIR"
    mkdir -p "$(dirname "$OMP_CHECKOUT_DIR")"
    git clone "$OMP_REPO" "$OMP_CHECKOUT_DIR"
fi
ok "omp source at $OMP_CHECKOUT_DIR"

# ─── Build ────────────────────────────────────────────────────────────────────
step "Building omp"

mkdir -p "$OMP_INSTALL_DIR"

# Use Makefile if present (preferred), otherwise fall back to go build
if [ -f "$OMP_CHECKOUT_DIR/Makefile" ]; then
    if make -C "$OMP_CHECKOUT_DIR" install INSTALL_DIR="$OMP_INSTALL_DIR" 2>/dev/null; then
        ok "omp built and installed via Makefile"
    else
        error "make install failed for omp"
        error "Try manually: cd $OMP_CHECKOUT_DIR && make install"
        exit 1
    fi
elif [ -f "$OMP_CHECKOUT_DIR/cmd/omp/main.go" ]; then
    if go build -C "$OMP_CHECKOUT_DIR" -o "$OMP_INSTALL_DIR/omp" ./cmd/omp/; then
        ok "omp built via go build"
    else
        error "go build failed for omp"
        exit 1
    fi
else
    error "No Makefile or cmd/omp/main.go found in $OMP_CHECKOUT_DIR"
    error "The omp repo structure may have changed."
    exit 1
fi

# Verify binary exists and is executable
if [ -x "${OMP_INSTALL_DIR}/omp" ]; then
    ok "omp installed at ${OMP_INSTALL_DIR}/omp ($(${OMP_INSTALL_DIR}/omp --version 2>/dev/null || echo 'unknown'))"
else
    error "omp binary not found at ${OMP_INSTALL_DIR}/omp after build"
    exit 1
fi
