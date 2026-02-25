#!/usr/bin/env bash
# lib/setup_opencode_auth.sh — Claude OAuth onboarding instructions
#
# Prints step-by-step instructions for authenticating OpenCode with Claude.
# Non-interactive: prints instructions and waits for user to press Enter,
# or skips the wait if --no-wait flag is passed.
#
# This script is intentionally instruction-only. It does not run `opencode auth`
# directly because authentication opens a browser, which requires user interaction.
# The wizard.sh step calls this and waits for the user to confirm completion.
#
# Flags:
#   --no-wait   Skip the "Press Enter to continue" prompt (for --yes mode)
#   --check     Check if auth is already configured (exit 0 if yes, 1 if no)
#
# Environment overrides:
#   OPENCODE_CONFIG_DIR  — opencode config dir (default: ~/.config/opencode)

set -uo pipefail

# ─── Colors (ayu-dark palette) ────────────────────────────────────────────────
C_STRING=$'\e[38;2;170;217;76m'    # #AAD94C green
C_ACCENT=$'\e[38;2;230;180;80m'    # #E6B450 golden yellow
C_TYPE=$'\e[38;2;89;194;255m'      # #59C2FF blue
C_KEYWORD=$'\e[38;2;255;143;64m'   # #FF8F40 orange
C_COMMENT=$'\e[38;2;98;109;122m'   # #626d7a gray
C_FG=$'\e[38;2;191;189;182m'       # #BFBDB6 foreground
C_RESET=$'\e[0m'

OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# ─── Flag parsing ─────────────────────────────────────────────────────────────
NO_WAIT=0
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-wait)   NO_WAIT=1;    shift ;;
        --check)     CHECK_ONLY=1; shift ;;
        *)           shift ;;
    esac
done

# ─── Auth check mode ──────────────────────────────────────────────────────────
# Check if opencode appears to have valid auth configured
_is_authenticated() {
    # opencode stores auth in ~/.config/opencode/ — look for auth.json or session tokens
    # This is a best-effort check; the definitive check is `opencode auth status`
    if [ -f "$OPENCODE_CONFIG_DIR/auth.json" ]; then
        # Check it has content (not empty/null)
        local content
        content=$(node -e "
try {
    const fs=require('fs');
    const c=JSON.parse(fs.readFileSync('$OPENCODE_CONFIG_DIR/auth.json','utf8'));
    process.exit(Object.keys(c).length > 0 ? 0 : 1);
} catch(e) { process.exit(1); }
" 2>/dev/null) && return 0
    fi

    # Try `opencode auth status` if opencode is installed
    if command -v opencode &>/dev/null; then
        opencode auth status &>/dev/null && return 0
    fi

    return 1
}

if [ "$CHECK_ONLY" -eq 1 ]; then
    if _is_authenticated; then
        echo "authenticated"
        exit 0
    else
        echo "not-authenticated"
        exit 1
    fi
fi

# ─── Print onboarding instructions ────────────────────────────────────────────
echo ""
echo -e "${C_STRING}╔══════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_STRING}║           Claude OAuth Authentication                ║${C_RESET}"
echo -e "${C_STRING}╚══════════════════════════════════════════════════════╝${C_RESET}"
echo ""
echo -e "${C_FG}OpenCode connects to Claude via OAuth. You'll need to authenticate${C_RESET}"
echo -e "${C_FG}once — your credentials are stored locally.${C_RESET}"
echo ""

# ─── Step 1: Check if opencode is installed ───────────────────────────────────
echo -e "${C_ACCENT}Step 1: Verify OpenCode is installed${C_RESET}"
if command -v opencode &>/dev/null; then
    echo -e "  ${C_STRING}✓${C_RESET} opencode found: $(command -v opencode)"
    _oc_ver=$(opencode --version 2>/dev/null || echo "unknown")
    echo -e "  ${C_COMMENT}  version: $_oc_ver${C_RESET}"
else
    echo -e "  ${C_KEYWORD}✗ opencode not found in PATH${C_RESET}"
    echo ""
    echo -e "  Install OpenCode first:"
    echo -e "  ${C_TYPE}  curl -fsSL https://opencode.ai/install | sh${C_RESET}"
    echo ""
    echo -e "  After installing, add to your shell profile:"
    echo -e "  ${C_TYPE}  export PATH=\"\$HOME/.local/bin:\$PATH\"${C_RESET}"
    echo ""
    if [ "$NO_WAIT" -eq 0 ]; then
        read -r -p "Press Enter once opencode is installed to continue..."
    fi
fi
echo ""

# ─── Step 2: Check existing auth ─────────────────────────────────────────────
echo -e "${C_ACCENT}Step 2: Check existing authentication${C_RESET}"
if _is_authenticated; then
    echo -e "  ${C_STRING}✓${C_RESET} Claude authentication already configured"
    echo -e "  ${C_COMMENT}  Config: $OPENCODE_CONFIG_DIR/auth.json${C_RESET}"
    echo ""
    echo -e "${C_STRING}You're already authenticated! No action needed.${C_RESET}"
    echo ""
    [ "$NO_WAIT" -eq 0 ] && read -r -p "Press Enter to continue..." || true
    exit 0
else
    echo -e "  ${C_COMMENT}No auth configured yet${C_RESET}"
fi
echo ""

# ─── Step 3: Run opencode auth login ─────────────────────────────────────────
echo -e "${C_ACCENT}Step 3: Authenticate with Claude${C_RESET}"
echo ""
echo -e "  Run the following command in your terminal:"
echo ""
echo -e "  ${C_TYPE}  opencode auth login${C_RESET}"
echo ""
echo -e "  ${C_FG}This will:${C_RESET}"
echo -e "  ${C_COMMENT}  1. Open your browser to the Anthropic OAuth page${C_RESET}"
echo -e "  ${C_COMMENT}  2. Ask you to sign in with your Anthropic account${C_RESET}"
echo -e "  ${C_COMMENT}  3. Grant OpenCode access to Claude${C_RESET}"
echo -e "  ${C_COMMENT}  4. Store credentials in $OPENCODE_CONFIG_DIR/auth.json${C_RESET}"
echo ""
echo -e "  ${C_FG}No Anthropic account? Create one at:${C_RESET}"
echo -e "  ${C_ACCENT}  https://console.anthropic.com/signup${C_RESET}"
echo ""

# ─── Step 4: Verify auth ──────────────────────────────────────────────────────
echo -e "${C_ACCENT}Step 4: Verify authentication${C_RESET}"
echo ""
echo -e "  After completing the browser login, verify it worked:"
echo ""
echo -e "  ${C_TYPE}  opencode auth status${C_RESET}"
echo ""
echo -e "  You should see your account email and an active session."
echo ""

# ─── Fallback: Manual prompt block ────────────────────────────────────────────
echo -e "${C_STRING}── Fallback: Paste into OpenCode ──────────────────────────${C_RESET}"
echo ""
echo -e "  If the browser auth doesn't work (e.g., headless server),"
echo -e "  you can paste the following prompt into OpenCode to test:"
echo ""
echo -e "  ${C_COMMENT}┌────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "  ${C_COMMENT}│ Hello! Can you confirm you can see this message?        │${C_RESET}"
echo -e "  ${C_COMMENT}│ If so, authentication is working correctly.             │${C_RESET}"
echo -e "  ${C_COMMENT}└────────────────────────────────────────────────────────┘${C_RESET}"
echo ""

# ─── Wait for user confirmation ───────────────────────────────────────────────
if [ "$NO_WAIT" -eq 0 ]; then
    echo -e "${C_ACCENT}Complete the authentication steps above, then press Enter to continue...${C_RESET}"
    read -r
    echo ""

    # Recheck auth after user says they're done
    if _is_authenticated; then
        echo -e "${C_STRING}✓ Authentication confirmed!${C_RESET}"
    else
        echo -e "${C_KEYWORD}⚠ Auth not detected yet.${C_RESET}"
        echo -e "  This is OK if you haven't run 'opencode auth login' yet."
        echo -e "  You can authenticate later by running: ${C_TYPE}opencode auth login${C_RESET}"
    fi
fi

echo ""
