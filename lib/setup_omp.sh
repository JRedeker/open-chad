#!/usr/bin/env bash
# lib/setup_omp.sh — Install opencode-model-preferences (omp) via go install
#
# Uses `go install` (official Go recommendation since 1.16) instead of
# git clone + make install. Idempotent by design, ~3 lines of actual work.
#
# Environment overrides:
#   OMP_VERSION      — version to install (default: latest)
#   OMP_INSTALL_DIR  — binary destination (default: ~/.local/bin)
#
# Called by install.sh. Safe to call standalone.

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
OMP_REPO="github.com/anomalyco/opencode-model-preferences"
OMP_VERSION="${OMP_VERSION:-latest}"
OMP_INSTALL_DIR="${OMP_INSTALL_DIR:-$HOME/.local/bin}"

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v go &>/dev/null; then
    warn "go not found in PATH. Skipping omp install."
    warn "To install omp later, install Go 1.16+ and run:"
    warn "  GOBIN=$OMP_INSTALL_DIR go install ${OMP_REPO}@${OMP_VERSION}"
    exit 0
fi

# ─── Install ─────────────────────────────────────────────────────────────────
step "Installing omp (${OMP_REPO}@${OMP_VERSION}) -> ${OMP_INSTALL_DIR}/omp"

mkdir -p "$OMP_INSTALL_DIR"

if GOBIN="$OMP_INSTALL_DIR" go install "${OMP_REPO}@${OMP_VERSION}"; then
    ok "omp installed at ${OMP_INSTALL_DIR}/omp"
else
    error "go install failed for ${OMP_REPO}@${OMP_VERSION}"
    error "Check your Go version (need 1.16+): go version"
    exit 1
fi

# Verify binary exists and is executable
if [ -x "${OMP_INSTALL_DIR}/omp" ]; then
    ok "omp is executable. Version: $(${OMP_INSTALL_DIR}/omp --version 2>/dev/null || echo 'unknown')"
else
    error "omp binary not found at ${OMP_INSTALL_DIR}/omp after install"
    exit 1
fi
