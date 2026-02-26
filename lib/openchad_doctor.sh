#!/usr/bin/env bash
# lib/openchad_doctor.sh — openchad doctor subcommand handler
#
# Validates the openchad installation:
#   - Managed symlinks exist and point to correct targets
#   - tmux theme block is present in ~/.tmux.conf
#   - Cache directory is writable
#   - Legacy open-chad symlink migration warning
#
# Called by: bin/openchad doctor

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_GREEN=$'\e[38;2;170;217;76m'    # #AAD94C string
C_YELLOW=$'\e[38;2;230;180;80m'   # #E6B450 accent
C_ORANGE=$'\e[38;2;255;143;64m'   # #FF8F40 keyword
C_GRAY=$'\e[38;2;98;109;122m'     # #626d7a comment
C_RESET=$'\e[0m'

ok()   { echo -e "  ${C_GREEN}✓${C_RESET} $*"; }
warn() { echo -e "  ${C_YELLOW}!${C_RESET} $*"; }
fail() { echo -e "  ${C_ORANGE}✗${C_RESET} $*"; }
info() { echo -e "  ${C_GRAY}·${C_RESET} $*"; }

_issues=0

echo ""
echo "openchad doctor — installation health check"
echo ""

# ─── 1. Managed symlinks ─────────────────────────────────────────────────────
echo "Symlinks (~/.local/bin):"

# Source the shared manifest
# shellcheck source=symlink_manifest.sh
source "$REPO_DIR/lib/symlink_manifest.sh"

DEST_DIR="$HOME/.local/bin"
for _link_name in "${!MANAGED_SYMLINKS[@]}"; do
    _expected_target="$REPO_DIR/${MANAGED_SYMLINKS[$_link_name]}"
    _link_path="$DEST_DIR/$_link_name"
    if [ -L "$_link_path" ]; then
        _actual_target=$(readlink -f "$_link_path" 2>/dev/null || echo "")
        if [ "$_actual_target" = "$_expected_target" ]; then
            ok "$_link_name → $_expected_target"
        else
            warn "$_link_name exists but points to wrong target"
            info "  expected: $_expected_target"
            info "  actual:   $_actual_target"
            _issues=$((_issues + 1))
        fi
    elif [ -e "$_link_path" ]; then
        fail "$_link_name exists but is not a symlink"
        _issues=$((_issues + 1))
    else
        fail "$_link_name missing — run: bash $REPO_DIR/install.sh"
        _issues=$((_issues + 1))
    fi
done
unset _link_name

# ─── 2. Legacy open-chad symlink migration warning ────────────────────────────
echo ""
echo "Legacy migration:"
if [ -L "$DEST_DIR/open-chad" ] || [ -e "$DEST_DIR/open-chad" ]; then
    warn "Stale 'open-chad' symlink found at $DEST_DIR/open-chad"
    info "  The canonical command is now 'openchad' (or 'oc' for short)."
    info "  Remove the stale symlink: rm $DEST_DIR/open-chad"
    _issues=$((_issues + 1))
else
    ok "No stale 'open-chad' symlink found"
fi

# Check for stale alias oc='open-chad' in shell rc files
_stale_alias_found=0
for _rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$_rc" ] && grep -qE "^[[:space:]]*alias[[:space:]]+oc=['\"]open-chad['\"]" "$_rc"; then
        warn "Stale alias oc='open-chad' in $_rc"
        info "  This overrides the oc symlink and causes 'command not found'."
        info "  Remove the line or run: openchad update"
        _stale_alias_found=1
        _issues=$((_issues + 1))
    fi
done
if [ "$_stale_alias_found" -eq 0 ]; then
    ok "No stale 'oc' alias found in shell rc files"
fi

# ─── 3. Tmux theme ───────────────────────────────────────────────────────────
echo ""
echo "Tmux theme:"
TMUX_CONF="$HOME/.tmux.conf"
if [ -f "$TMUX_CONF" ] && grep -q 'OPEN-CHAD THEME' "$TMUX_CONF"; then
    ok "Theme block present in $TMUX_CONF"
else
    fail "Theme block missing from $TMUX_CONF"
    info "  Run: bash $REPO_DIR/install.sh --yes to add it"
    _issues=$((_issues + 1))
fi

# ─── 4. Cache directory ───────────────────────────────────────────────────────
echo ""
echo "Cache directory:"
# Source Claude_env.sh to resolve OPEN_CHAD_CACHE_DIR
if [ -f "$REPO_DIR/lib/Claude_env.sh" ]; then
    # shellcheck source=Claude_env.sh
    source "$REPO_DIR/lib/Claude_env.sh"
fi
_cache_dir="${OPEN_CHAD_CACHE_DIR:-/tmp/open-chad-${USER:-unknown}}"
if [ -d "$_cache_dir" ] && [ -w "$_cache_dir" ]; then
    ok "Cache dir writable: $_cache_dir"
elif [ ! -d "$_cache_dir" ]; then
    warn "Cache dir not yet created: $_cache_dir (created on first launch)"
else
    fail "Cache dir not writable: $_cache_dir"
    _issues=$((_issues + 1))
fi

# ─── 5. Vision daemon ────────────────────────────────────────────────────────
echo ""
echo "Vision daemon (MCP server manager):"

if ! command -v vision &>/dev/null; then
    fail "vision binary not found on PATH"
    info "  Vision is required for MCP tools (context7, grep-app, lgrep, firecrawl)."
    info "  Install Vision and ensure it is on PATH."
    info "  Then re-run: bash $REPO_DIR/lib/setup_vision.sh"
    _issues=$((_issues + 1))
else
    ok "vision binary: $(command -v vision)"

    # Check daemon status
    if vision daemon status 2>/dev/null | grep -q "running"; then
        ok "Vision daemon running"
    else
        fail "Vision daemon not running"
        info "  Start with: openchad (auto-starts on launch)"
        info "  Or manually: vision daemon start &"
        _issues=$((_issues + 1))
    fi

    # Check all 4 MCP ports (2-second timeout each)
    _vision_ports=(6276 6288 6285 6281)
    _vision_names=(context7 grep-app lgrep firecrawl)
    for _i in "${!_vision_ports[@]}"; do
        _port="${_vision_ports[$_i]}"
        _name="${_vision_names[$_i]}"
        if curl -sf --max-time 2 "http://localhost:${_port}/mcp" >/dev/null 2>&1; then
            ok "Port ${_port} (${_name}): reachable"
        else
            fail "Port ${_port} (${_name}): not reachable"
            info "  Vision daemon may not have started ${_name} yet."
            info "  Check: $REPO_DIR/../cache/vision.log (or \$OPEN_CHAD_CACHE_DIR/vision.log)"
            _issues=$((_issues + 1))
        fi
    done
    unset _i _port _name _vision_ports _vision_names
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
if [ "$_issues" -eq 0 ]; then
    echo -e "${C_GREEN}All checks passed.${C_RESET} openchad is healthy."
else
    echo -e "${C_ORANGE}$_issues issue(s) found.${C_RESET} Run 'openchad update' to repair symlinks."
fi
echo ""
exit "$_issues"
