#!/usr/bin/env bash
# lib/setup_dev_bundle.sh — Developer language toolchain installer
#
# Installs selected language bundles. Each bundle is idempotent — safe to re-run.
#
# Bundles:
#   python  — uv (Python version manager + package manager), ruff, pyrefly, ty
#             Wire pyrefly as LSP in opencode.json
#   go      — Go via apt + upgrade to latest stable via tarball if apt version < 1.21
#   rust    — Rust via rustup --profile minimal (stable toolchain)
#
# uv-only policy (R3): Python version management is handled entirely by uv.
# pyenv is NOT installed — uv python install <version> replaces it.
#
# Install state (R4): Selected bundles written to:
#   ~/.config/opencode/open-chad.json under installer.selectedBundles
# This allows `open-chad update` to re-apply the same bundles on update.
#
# Environment overrides:
#   OPEN_CHAD_BUNDLES       — space-separated: "python go rust" (set by wizard)
#   OPEN_CHAD_CONFIG_FILE   — open-chad.json path (default: ~/.config/opencode/open-chad.json)
#   OPENCODE_CONFIG_DIR     — opencode config dir (default: ~/.config/opencode)
#   OPEN_CHAD_INSTALL_LOG   — log file (default: /tmp/open-chad-install.log)
#
# Called by wizard.sh (after bundle selection) and update.sh. Safe to call standalone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[bundle]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[bundle] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[bundle] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[bundle] ERROR:${C_RESET} $*" >&2; }
hint()  { echo -e "${C_CORAL}         ↳${C_RESET} $*" >&2; }
log()   { echo "[$(date -Iseconds)] bundle: $*" >> "$INSTALL_LOG"; }

# ─── Configuration ────────────────────────────────────────────────────────────
BUNDLES="${OPEN_CHAD_BUNDLES:-}"
OPEN_CHAD_CONFIG_FILE="${OPEN_CHAD_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"

if [ -z "$BUNDLES" ]; then
    warn "No bundles selected (OPEN_CHAD_BUNDLES is empty). Nothing to install."
    exit 0
fi

log "Starting bundle installs: $BUNDLES"

# ─── Sudo helper ──────────────────────────────────────────────────────────────
_SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
    _SUDO="sudo"
fi

# ─── State persistence helper ─────────────────────────────────────────────────
# Write installer.selectedBundles to open-chad.json (idempotent via json_merge)
_persist_bundles() {
    local bundles_json
    bundles_json="$(echo "$BUNDLES" | tr ' ' '\n' | grep -v '^$' | \
        awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')"

    mkdir -p "$(dirname "$OPEN_CHAD_CONFIG_FILE")"
    [ -f "$OPEN_CHAD_CONFIG_FILE" ] || echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    node -e "
const fs = require('fs');
let c = {};
try { c = JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE', 'utf8')); } catch(e) {}
if (!c.installer) c.installer = {};
c.installer.selectedBundles = $bundles_json;
c.installer.lastUpdated = new Date().toISOString();
fs.writeFileSync('$OPEN_CHAD_CONFIG_FILE', JSON.stringify(c, null, 2) + '\n');
" 2>/dev/null || warn "Could not persist bundle state to $OPEN_CHAD_CONFIG_FILE"
    log "Persisted selectedBundles: $bundles_json to $OPEN_CHAD_CONFIG_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PYTHON BUNDLE — uv only (R3: no pyenv)
# ═══════════════════════════════════════════════════════════════════════════════
_install_python_bundle() {
    step "Python bundle: installing uv"

    # uv installation via official script (idempotent)
    if command -v uv &>/dev/null; then
        _uv_ver=$(uv --version 2>/dev/null | awk '{print $2}')
        ok "uv $_uv_ver already installed"
        # Self-update
        uv self update >> "$INSTALL_LOG" 2>&1 || true
    else
        step "Downloading and installing uv from astral.sh"
        log "Installing uv via astral.sh"
        curl -LsSf https://astral.sh/uv/install.sh | sh >> "$INSTALL_LOG" 2>&1 || {
            error "uv install failed. Check network connectivity and $INSTALL_LOG"
            hint "Manual install: curl -LsSf https://astral.sh/uv/install.sh | sh"
            return 1
        }
        # Source uv into PATH for this session
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        ok "uv installed"
    fi

    # Ensure uv is in PATH for remaining steps
    if ! command -v uv &>/dev/null; then
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    fi

    # Install latest stable Python via uv (no pyenv needed)
    step "Installing Python 3.12 (latest stable) via uv"
    uv python install 3.12 >> "$INSTALL_LOG" 2>&1 || {
        warn "uv python install 3.12 failed. Trying without version pin."
        uv python install >> "$INSTALL_LOG" 2>&1 || true
    }
    ok "Python installed via uv"

    # Install dev tools via uv tool install
    for tool in ruff pyrefly ty; do
        step "Installing $tool via uv tool install"
        if uv tool install "$tool" >> "$INSTALL_LOG" 2>&1; then
            ok "$tool installed"
        else
            warn "$tool install failed (non-fatal) — check $INSTALL_LOG"
        fi
    done

    # Wire pyrefly as LSP in opencode.json
    # Schema: lsp.<name>.command (array), lsp.<name>.extensions (array)
    # The key name must match the LSP server name, not the language name.
    if command -v pyrefly &>/dev/null || [ -f "$HOME/.local/bin/pyrefly" ]; then
        step "Wiring pyrefly LSP into $OPENCODE_JSON"
        mkdir -p "$OPENCODE_CONFIG_DIR"
        [ -f "$OPENCODE_JSON" ] || echo '{}' > "$OPENCODE_JSON"
        bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
            '{"lsp":{"pyrefly":{"command":["pyrefly","lsp"],"extensions":[".py",".pyi"]}}}' \
            >> "$INSTALL_LOG" 2>&1 || warn "Could not wire pyrefly LSP"
        ok "pyrefly LSP wired into opencode.json"
    else
        warn "pyrefly not found in PATH — skipping LSP config. Install manually: uv tool install pyrefly"
    fi

    log "Python bundle complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GO BUNDLE — apt first, tarball upgrade if < 1.21
# ═══════════════════════════════════════════════════════════════════════════════
_install_go_bundle() {
    step "Go bundle: checking existing installation"

    # Minimum acceptable Go version
    local MIN_GO_MAJOR=1 MIN_GO_MINOR=21

    _go_ok=0
    if command -v go &>/dev/null; then
        _go_ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
        _go_major=$(echo "$_go_ver" | cut -d. -f1)
        _go_minor=$(echo "$_go_ver" | cut -d. -f2)
        if [ "${_go_major:-0}" -gt "$MIN_GO_MAJOR" ] || \
           ([ "${_go_major:-0}" -eq "$MIN_GO_MAJOR" ] && [ "${_go_minor:-0}" -ge "$MIN_GO_MINOR" ]); then
            ok "Go $_go_ver already installed (>= ${MIN_GO_MAJOR}.${MIN_GO_MINOR})"
            _go_ok=1
        else
            warn "Go $_go_ver found but < ${MIN_GO_MAJOR}.${MIN_GO_MINOR} — upgrading via tarball"
        fi
    fi

    if [ "$_go_ok" -eq 0 ]; then
        # Try apt first (may be outdated but fast)
        if ! command -v go &>/dev/null; then
            step "Installing Go via apt"
            DEBIAN_FRONTEND=noninteractive $_SUDO apt-get install -qq -y --no-install-recommends \
                golang-go >> "$INSTALL_LOG" 2>&1 || warn "apt golang-go install failed"
        fi

        # Check if apt gave us a fresh enough version
        _go_ok=0
        if command -v go &>/dev/null; then
            _go_ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
            _go_major=$(echo "$_go_ver" | cut -d. -f1)
            _go_minor=$(echo "$_go_ver" | cut -d. -f2)
            if [ "${_go_major:-0}" -gt "$MIN_GO_MAJOR" ] || \
               ([ "${_go_major:-0}" -eq "$MIN_GO_MAJOR" ] && [ "${_go_minor:-0}" -ge "$MIN_GO_MINOR" ]); then
                ok "Go $_go_ver (from apt) is sufficient"
                _go_ok=1
            fi
        fi

        # Tarball install for latest stable
        if [ "$_go_ok" -eq 0 ]; then
            step "Installing Go via official tarball (latest stable)"
            log "Fetching latest Go version from go.dev"

            # Keep fallback in sync with current stable listed on go.dev/dl.
            _go_latest=$(curl -fsSL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 || echo "go1.26.0")
            _go_tarball="${_go_latest}.linux-amd64.tar.gz"
            _go_url="https://go.dev/dl/${_go_tarball}"
            _go_sha_url="${_go_url}.sha256"

            step "Downloading ${_go_tarball}"
            local _tmp_tar _tmp_sha _expected_sha _actual_sha
            _tmp_tar=$(mktemp /tmp/go-XXXXXX.tar.gz)
            curl -fsSL "$_go_url" -o "$_tmp_tar" >> "$INSTALL_LOG" 2>&1 || {
                error "Failed to download Go tarball: $_go_url"
                hint "Check network connectivity and try again."
                rm -f "$_tmp_tar"
                return 1
            }

            if ! command -v sha256sum &>/dev/null; then
                error "sha256sum not found; cannot verify Go tarball integrity."
                hint "Install coreutils and retry."
                rm -f "$_tmp_tar"
                return 1
            fi

            step "Verifying ${_go_tarball} checksum"
            _tmp_sha=$(mktemp /tmp/go-XXXXXX.sha256)
            curl -fsSL "$_go_sha_url" -o "$_tmp_sha" >> "$INSTALL_LOG" 2>&1 || {
                error "Failed to download Go checksum file: $_go_sha_url"
                hint "Cannot safely install without checksum verification."
                rm -f "$_tmp_tar" "$_tmp_sha"
                return 1
            }

            _expected_sha=$(tr -d '[:space:]' < "$_tmp_sha")
            _actual_sha=$(sha256sum "$_tmp_tar" | awk '{print $1}')
            if [ -z "$_expected_sha" ] || [ "$_actual_sha" != "$_expected_sha" ]; then
                error "Go tarball SHA256 verification failed."
                hint "Expected: ${_expected_sha:-<empty>}"
                hint "Actual:   ${_actual_sha:-<empty>}"
                rm -f "$_tmp_tar" "$_tmp_sha"
                return 1
            fi

            if ! tar -tzf "$_tmp_tar" >/dev/null 2>&1; then
                error "Downloaded Go tarball is invalid or corrupted."
                rm -f "$_tmp_tar" "$_tmp_sha"
                return 1
            fi

            step "Installing Go to /usr/local/go"
            $_SUDO rm -rf /usr/local/go
            $_SUDO tar -C /usr/local -xzf "$_tmp_tar" >> "$INSTALL_LOG" 2>&1
            rm -f "$_tmp_tar" "$_tmp_sha"

            # Add to PATH for this session
            export PATH="/usr/local/go/bin:$PATH"
            ok "Go $(_go_ver=$(go version 2>/dev/null | awk '{print $3}'); echo ${_go_ver#go}) installed via tarball"
        fi
    fi

    # Add ~/.local/bin to PATH in shell profile via centralized helper (idempotent)
    bash "$REPO_DIR/lib/setup_shell_profile.sh" || true
    # Also ensure Go bins are in PATH for this session
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

    log "Go bundle complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUST BUNDLE — rustup minimal
# ═══════════════════════════════════════════════════════════════════════════════
_install_rust_bundle() {
    step "Rust bundle: checking existing installation"

    if command -v rustup &>/dev/null; then
        ok "rustup already installed ($(rustup --version 2>/dev/null | head -1))"
        step "Updating Rust toolchain"
        rustup update stable >> "$INSTALL_LOG" 2>&1 || warn "rustup update failed (non-fatal)"
        ok "Rust stable updated"
        return 0
    fi

    step "Installing Rust via rustup (profile: minimal)"
    log "Installing rustup"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --profile minimal --default-toolchain stable \
        >> "$INSTALL_LOG" 2>&1 || {
        error "rustup install failed. Check $INSTALL_LOG"
        hint "Manual install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        return 1
    }

    # Source cargo into PATH for this session
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    export PATH="$HOME/.cargo/bin:$PATH"

    ok "Rust stable installed ($(rustc --version 2>/dev/null || echo 'unknown'))"
    log "Rust bundle complete"
}

# ─── Main: iterate selected bundles ───────────────────────────────────────────
_failed_bundles=()

for bundle in $BUNDLES; do
    case "$bundle" in
        python)
            echo -e "\n${C_SAGE}── Python Bundle ──────────────────────────────────${C_RESET}"
            _install_python_bundle || _failed_bundles+=("python")
            ;;
        go)
            echo -e "\n${C_SAGE}── Go Bundle ──────────────────────────────────────${C_RESET}"
            _install_go_bundle || _failed_bundles+=("go")
            ;;
        rust)
            echo -e "\n${C_SAGE}── Rust Bundle ────────────────────────────────────${C_RESET}"
            _install_rust_bundle || _failed_bundles+=("rust")
            ;;
        *)
            warn "Unknown bundle: $bundle (skipping)"
            ;;
    esac
done

# ─── Summary ──────────────────────────────────────────────────────────────────
if [ "${#_failed_bundles[@]}" -gt 0 ]; then
    warn "The following bundles had errors: ${_failed_bundles[*]}"
    warn "Check $INSTALL_LOG for details."
    echo ""
    echo -e "${C_CORAL}  Recovery guide:${C_RESET}"
    for _fb in "${_failed_bundles[@]}"; do
        case "$_fb" in
            python)
                echo -e "    ${C_GOLD}Python:${C_RESET} curl -LsSf https://astral.sh/uv/install.sh | sh"
                echo -e "           Then: uv python install 3.12 && uv tool install ruff pyrefly ty"
                ;;
            go)
                echo -e "    ${C_GOLD}Go:${C_RESET}     Download from https://go.dev/dl/ and extract to /usr/local/go"
                echo -e "           Or: sudo snap install go --classic"
                ;;
            rust)
                echo -e "    ${C_GOLD}Rust:${C_RESET}   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                ;;
        esac
    done
    echo ""
    warn "Retry failed bundles: OPEN_CHAD_BUNDLES=\"${_failed_bundles[*]}\" bash lib/setup_dev_bundle.sh"
    exit 1
fi

# ─── Persist install state (R4) ───────────────────────────────────────────────
_persist_bundles

ok "All selected bundles installed: $BUNDLES"
ok "Bundle state saved to: $OPEN_CHAD_CONFIG_FILE"
