#!/usr/bin/env bash
# tests/discord_bridge_test.sh — Unit tests for lib/discord/wsl_bridge.sh
#
# Tests WSL detection, dependency checks, idempotent bridge lifecycle,
# stale PID/socket cleanup, and status output variants.
#
# Exit code = number of failures (0 = all pass).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_SH="$REPO_DIR/lib/discord/wsl_bridge.sh"

# ─── Test framework ───────────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS: $*"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $*"; }
skip() { TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); echo "  SKIP: $*"; }

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    [ "$actual" = "$expected" ] && pass "$msg" || fail "$msg (expected '$expected', got '$actual')"
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    [[ "$haystack" == *"$needle"* ]] && pass "$msg" || fail "$msg (looking for '$needle' in: $haystack)"
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    [[ "$haystack" != *"$needle"* ]] && pass "$msg" || fail "$msg (unexpectedly found '$needle')"
}

section() { echo ""; echo "── $* ──"; }

# ─── Helpers ─────────────────────────────────────────────────────────────────

TMP_DIR=""
setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    export OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache"
    mkdir -p "$OPEN_CHAD_CACHE_DIR"
}

teardown_tmp_env() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR" || true
    unset OPEN_CHAD_CACHE_DIR
    TMP_DIR=""
}

# Source bridge functions into current shell with overrideable env
source_bridge() {
    local proc_version="${1:-}"
    local wsl_interop="${2:-}"

    # Override /proc/version detection by injecting a fake file path
    if [ -n "$proc_version" ]; then
        local fake_proc="$TMP_DIR/proc_version"
        echo "$proc_version" > "$fake_proc"
        OPEN_CHAD_PROC_VERSION="$fake_proc" source "$BRIDGE_SH"
    else
        source "$BRIDGE_SH"
    fi
}

# ─── Section 1: Preconditions ─────────────────────────────────────────────────

section "Preconditions: wsl_bridge.sh exists and is executable"

if [ ! -f "$BRIDGE_SH" ]; then
    fail "wsl_bridge.sh not found at $BRIDGE_SH"
    echo ""
    echo "════════════════════════════════════"
    echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
    echo "════════════════════════════════════"
    exit "$TESTS_FAILED"
fi

[ -f "$BRIDGE_SH" ] && pass "wsl_bridge.sh exists" || fail "wsl_bridge.sh missing"
[ -x "$BRIDGE_SH" ] && pass "wsl_bridge.sh is executable" || fail "wsl_bridge.sh not executable"
bash -n "$BRIDGE_SH" 2>/dev/null && pass "wsl_bridge.sh syntax OK" || fail "wsl_bridge.sh syntax error"

# ─── Section 2: _is_wsl detection ─────────────────────────────────────────────

section "_is_wsl detection"

test_is_wsl_true_on_microsoft_kernel() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" bash -c "
        source '$BRIDGE_SH'
        _is_wsl && echo 'yes' || echo 'no'
    " 2>/dev/null)
    assert_eq "$result" "yes" "_is_wsl returns true on Microsoft kernel"
    teardown_tmp_env
}

test_is_wsl_true_on_wsl_interop() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.0-generic" > "$fake_proc"
    local fake_interop="$TMP_DIR/wsl_interop"
    touch "$fake_interop"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" OPEN_CHAD_WSL_INTEROP="$fake_interop" bash -c "
        source '$BRIDGE_SH'
        _is_wsl && echo 'yes' || echo 'no'
    " 2>/dev/null)
    assert_eq "$result" "yes" "_is_wsl returns true when WSL_INTEROP file exists"
    teardown_tmp_env
}

test_is_wsl_false_on_native_linux() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.0-generic (Ubuntu)" > "$fake_proc"
    local fake_interop="$TMP_DIR/no_interop_here"  # does not exist

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" OPEN_CHAD_WSL_INTEROP="$fake_interop" bash -c "
        source '$BRIDGE_SH'
        _is_wsl && echo 'yes' || echo 'no'
    " 2>/dev/null)
    assert_eq "$result" "no" "_is_wsl returns false on native Linux"
    teardown_tmp_env
}

test_is_wsl_false_when_no_proc_version() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/nonexistent_proc_version"  # does not exist
    local fake_interop="$TMP_DIR/no_interop"             # does not exist

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" OPEN_CHAD_WSL_INTEROP="$fake_interop" bash -c "
        source '$BRIDGE_SH'
        _is_wsl && echo 'yes' || echo 'no'
    " 2>/dev/null)
    assert_eq "$result" "no" "_is_wsl returns false when /proc/version absent"
    teardown_tmp_env
}

test_is_wsl_true_on_microsoft_case_insensitive() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-Microsoft-Standard" > "$fake_proc"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" bash -c "
        source '$BRIDGE_SH'
        _is_wsl && echo 'yes' || echo 'no'
    " 2>/dev/null)
    assert_eq "$result" "yes" "_is_wsl is case-insensitive for Microsoft"
    teardown_tmp_env
}

test_is_wsl_true_on_microsoft_kernel
test_is_wsl_true_on_wsl_interop
test_is_wsl_false_on_native_linux
test_is_wsl_false_when_no_proc_version
test_is_wsl_true_on_microsoft_case_insensitive

# ─── Section 3: _wsl_bridge_deps_ok ──────────────────────────────────────────

section "_wsl_bridge_deps_ok dependency checks"

test_deps_ok_when_both_present() {
    setup_tmp_env
    # Create fake binaries in a temp bin dir
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"

    local result
    result=$(PATH="$fake_bin:$PATH" OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_deps_ok && echo 'ok' || echo 'missing'
    " 2>/dev/null)
    assert_eq "$result" "ok" "_wsl_bridge_deps_ok returns ok when both socat and npiperelay.exe present"
    teardown_tmp_env
}

test_deps_missing_socat() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # socat NOT in fake_bin — use only fake_bin in PATH (no /bin or /usr/bin)
    # On Ubuntu, /bin is a symlink to /usr/bin where socat lives
    # Also disable GOPATH fallback to prevent finding cross-compiled binary.
    local isolated_path="$fake_bin"

    local result
    result=$(PATH="$isolated_path" OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" \
        OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 /bin/bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_deps_ok && echo 'ok' || echo 'missing'
    " 2>/dev/null)
    assert_eq "$result" "missing" "_wsl_bridge_deps_ok returns missing when socat absent"
    teardown_tmp_env
}

test_deps_missing_npiperelay() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    # npiperelay.exe NOT present - disable GOPATH fallback for isolation
    # Use only fake_bin:/bin to avoid finding real socat in /usr/bin

    local result
    result=$(PATH="$fake_bin:/bin" OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" \
        OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 /bin/bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_deps_ok && echo 'ok' || echo 'missing'
    " 2>/dev/null)
    assert_eq "$result" "missing" "_wsl_bridge_deps_ok returns missing when npiperelay.exe absent"
    teardown_tmp_env
}

test_deps_ok_when_both_present
test_deps_missing_socat
test_deps_missing_npiperelay

# ─── Section 4: _wsl_bridge_status ───────────────────────────────────────────

section "_wsl_bridge_status output variants"

test_status_not_wsl() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.0-generic" > "$fake_proc"
    local fake_interop="$TMP_DIR/no_interop"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" OPEN_CHAD_WSL_INTEROP="$fake_interop" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_status
    " 2>/dev/null)
    assert_eq "$result" "not-wsl" "_wsl_bridge_status returns 'not-wsl' on native Linux"
    teardown_tmp_env
}

test_status_missing_deps() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    # Check if we can isolate from socat
    # On Ubuntu, /bin is a symlink to /usr/bin where socat may be installed
    if command -v socat &>/dev/null; then
        skip "_wsl_bridge_status missing-deps test: socat installed, cannot isolate"
        teardown_tmp_env
        return
    fi
    # Use PATH without socat
    local isolated_path="/usr/bin:/bin"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$isolated_path" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" \
        OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 /bin/bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_status
    " 2>/dev/null)
    assert_eq "$result" "missing-deps" "_wsl_bridge_status returns 'missing-deps' when deps absent on WSL"
    teardown_tmp_env
}

test_status_not_running() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # No PID file

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$fake_bin:$PATH" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_status
    " 2>/dev/null)
    assert_eq "$result" "not-running" "_wsl_bridge_status returns 'not-running' when deps ok but no PID file"
    teardown_tmp_env
}

test_status_ready_with_live_pid() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # Write our own PID as the bridge PID (we know it's alive)
    echo "$$" > "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$fake_bin:$PATH" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_status
    " 2>/dev/null)
    assert_eq "$result" "ready" "_wsl_bridge_status returns 'ready' when PID file exists and process alive"
    teardown_tmp_env
}

test_status_not_running_with_dead_pid() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # Write a dead PID (99999999 is almost certainly not running)
    echo "99999999" > "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$fake_bin:$PATH" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_status
    " 2>/dev/null)
    assert_eq "$result" "not-running" "_wsl_bridge_status returns 'not-running' when PID file has dead PID"
    teardown_tmp_env
}

test_status_not_wsl
test_status_missing_deps
test_status_not_running
test_status_ready_with_live_pid
test_status_not_running_with_dead_pid

# ─── Section 5: _wsl_bridge_ensure idempotency ───────────────────────────────

section "_wsl_bridge_ensure idempotency and stale cleanup"

test_ensure_skips_if_already_running() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # Pre-populate PID file with our own PID (alive)
    echo "$$" > "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$fake_bin:$PATH" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_ensure 2>&1
        echo exit:\$?
    " 2>/dev/null)
    assert_contains "$result" "exit:0" "_wsl_bridge_ensure exits 0 when already running"
    assert_contains "$result" "already running" "_wsl_bridge_ensure skips start when already running"
    teardown_tmp_env
}

test_ensure_cleans_stale_pid_and_socket() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    # socat that just exits 0 (simulates bridge start without actually bridging)
    echo '#!/bin/sh
echo "socat started" >&2
sleep 0' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"

    # Stale PID file (dead process)
    echo "99999999" > "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid"
    # Stale socket
    touch "/tmp/discord-ipc-0" 2>/dev/null || true

    OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$fake_bin:$PATH" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_ensure 2>/dev/null
    " 2>/dev/null || true

    # Stale PID file should be gone or replaced
    if [ -f "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid" ]; then
        local new_pid
        new_pid=$(cat "$OPEN_CHAD_CACHE_DIR/discord-bridge.pid")
        [ "$new_pid" != "99999999" ] && pass "_wsl_bridge_ensure replaced stale PID file" \
            || fail "_wsl_bridge_ensure did not replace stale PID (still 99999999)"
    else
        pass "_wsl_bridge_ensure removed stale PID file"
    fi
    teardown_tmp_env
}

test_ensure_noop_on_non_wsl() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.0-generic" > "$fake_proc"
    local fake_interop="$TMP_DIR/no_interop"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" OPEN_CHAD_WSL_INTEROP="$fake_interop" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_ensure 2>&1
        echo exit:\$?
    " 2>/dev/null)
    assert_contains "$result" "exit:0" "_wsl_bridge_ensure exits 0 on non-WSL"
    assert_not_contains "$result" "socat" "_wsl_bridge_ensure does not start socat on non-WSL"
    teardown_tmp_env
}

test_ensure_noop_when_deps_missing() {
    setup_tmp_env
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    # Check if we can isolate from socat
    # On Ubuntu, /bin is a symlink to /usr/bin where socat may be installed
    if command -v socat &>/dev/null; then
        skip "_wsl_bridge_ensure missing-deps test: socat installed, cannot isolate"
        teardown_tmp_env
        return
    fi
    # Use PATH without socat
    local isolated_path="/usr/bin:/bin"

    local result
    result=$(OPEN_CHAD_PROC_VERSION="$fake_proc" PATH="$isolated_path" \
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR" \
        OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 /bin/bash -c "
        source '$BRIDGE_SH'
        _wsl_bridge_ensure 2>&1
        echo exit:\$?
    " 2>/dev/null)
    assert_contains "$result" "exit:0" "_wsl_bridge_ensure exits 0 when deps missing (non-fatal)"
    assert_contains "$result" "missing" "_wsl_bridge_ensure logs missing deps"
    teardown_tmp_env
}

test_ensure_skips_if_already_running
test_ensure_cleans_stale_pid_and_socket
test_ensure_noop_on_non_wsl
test_ensure_noop_when_deps_missing

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
