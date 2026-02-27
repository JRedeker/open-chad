#!/usr/bin/env bash
# lib/discord/wsl_bridge.sh — WSL Discord IPC bridge manager
#
# Bridges the Windows Discord named pipe to a Linux Unix socket so that
# @xhayper/discord-rpc can connect from WSL2 to the Windows Discord client.
#
# Bridge: socat UNIX-LISTEN:/tmp/discord-ipc-0 EXEC:"npiperelay.exe //./pipe/discord-ipc-0"
#
# Functions (source this file to use):
#   _is_wsl              — returns 0 if running under WSL2, 1 otherwise
#   _wsl_bridge_deps_ok  — returns 0 if socat + npiperelay.exe are on PATH
#   _wsl_bridge_ensure   — idempotent bridge start (non-fatal, fire-and-forget)
#   _wsl_bridge_stop     — stop the bridge and clean up PID/socket
#   _wsl_bridge_status   — echo one of: not-wsl / missing-deps / not-running / ready
#
# Environment overrides (for testing):
#   OPEN_CHAD_PROC_VERSION   — path to /proc/version substitute (default: /proc/version)
#   OPEN_CHAD_WSL_INTEROP    — path to WSL_INTEROP file substitute (default: /proc/sys/fs/binfmt_misc/WSLInterop)
#   OPEN_CHAD_CACHE_DIR      — cache directory for PID file and lock (required)
#   OPEN_CHAD_BRIDGE_SOCKET  — Unix socket path (default: /tmp/discord-ipc-0)
#   OPEN_CHAD_BRIDGE_PIPE    — Windows named pipe path (default: //./pipe/discord-ipc-0)

# ─── Constants ────────────────────────────────────────────────────────────────

_BRIDGE_SOCKET="${OPEN_CHAD_BRIDGE_SOCKET:-/tmp/discord-ipc-0}"
_BRIDGE_PIPE="${OPEN_CHAD_BRIDGE_PIPE:-//./pipe/discord-ipc-0}"
_BRIDGE_PID_FILE="${OPEN_CHAD_CACHE_DIR:-/tmp/open-chad-${USER:-user}}/discord-bridge.pid"
_BRIDGE_LOCK_DIR="${OPEN_CHAD_CACHE_DIR:-/tmp/open-chad-${USER:-user}}/discord-bridge.lock"
_BRIDGE_LOG="${OPEN_CHAD_CACHE_DIR:-/tmp/open-chad-${USER:-user}}/discord-bridge.log"

# Testable /proc/version path (override in tests)
_PROC_VERSION="${OPEN_CHAD_PROC_VERSION:-/proc/version}"
# Testable WSL interop path (override in tests)
_WSL_INTEROP_PATH="${OPEN_CHAD_WSL_INTEROP:-/proc/sys/fs/binfmt_misc/WSLInterop}"

# ─── _is_wsl ─────────────────────────────────────────────────────────────────
# Returns 0 (true) if running under WSL2, 1 (false) otherwise.
# Detection: /proc/version contains "microsoft" (case-insensitive) OR
#            WSL_INTEROP file exists (set by WSL kernel).
_is_wsl() {
    if [ -f "$_PROC_VERSION" ] && grep -qi "microsoft" "$_PROC_VERSION" 2>/dev/null; then
        return 0
    fi
    if [ -f "$_WSL_INTEROP_PATH" ]; then
        return 0
    fi
    return 1
}

# ─── _wsl_bridge_get_npiperelay ──────────────────────────────────────────────
# Returns the path to npiperelay.exe, or empty string if not found.
# Checks PATH first, then GOPATH/bin/windows_amd64/ for cross-compiled binary.
# Set OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 to skip GOPATH check (for testing).
_wsl_bridge_get_npiperelay() {
    local _npiperelay
    
    # Check PATH first
    _npiperelay=$(command -v npiperelay.exe 2>/dev/null) && echo "$_npiperelay" && return 0
    
    # Fallback: check GOPATH/bin/windows_amd64/ for cross-compiled binary
    # Skip if explicitly disabled (for isolated testing)
    if [ "${OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK:-0}" != "1" ]; then
        local _gopath
        _gopath="${GOPATH:-$(go env GOPATH 2>/dev/null || echo "$HOME/go")}"
        if [ -x "$_gopath/bin/windows_amd64/npiperelay.exe" ]; then
            echo "$_gopath/bin/windows_amd64/npiperelay.exe"
            return 0
        fi
    fi
    
    # Not found
    echo ""
    return 1
}

# ─── _wsl_bridge_deps_ok ─────────────────────────────────────────────────────
# Returns 0 if both socat and npiperelay.exe are on PATH, 1 otherwise.
# Uses command -v (POSIX) instead of bash-specific 'type -P' for zsh compatibility.
# Also checks GOPATH/bin/windows_amd64 for cross-compiled npiperelay.exe.
_wsl_bridge_deps_ok() {
    # Check for socat (required)
    command -v socat &>/dev/null || return 1
    
    # Check for npiperelay.exe via helper (PATH or GOPATH/bin/windows_amd64)
    _wsl_bridge_get_npiperelay &>/dev/null
}

# ─── _wsl_bridge_pid_alive ───────────────────────────────────────────────────
# Returns 0 if PID file exists and the process is alive, 1 otherwise.
_wsl_bridge_pid_alive() {
    if [ ! -f "$_BRIDGE_PID_FILE" ]; then
        return 1
    fi
    local pid
    pid=$(cat "$_BRIDGE_PID_FILE" 2>/dev/null || echo "")
    if [ -z "$pid" ]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

# ─── _wsl_bridge_status ──────────────────────────────────────────────────────
# Outputs one of: not-wsl / missing-deps / not-running / ready
_wsl_bridge_status() {
    if ! _is_wsl; then
        echo "not-wsl"
        return 0
    fi
    if ! _wsl_bridge_deps_ok; then
        echo "missing-deps"
        return 0
    fi
    if _wsl_bridge_pid_alive; then
        echo "ready"
    else
        echo "not-running"
    fi
}

# ─── _wsl_bridge_cleanup_stale ───────────────────────────────────────────────
# Remove stale PID file and socket if the recorded process is dead.
_wsl_bridge_cleanup_stale() {
    if [ -f "$_BRIDGE_PID_FILE" ]; then
        local pid
        pid=$(cat "$_BRIDGE_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$_BRIDGE_PID_FILE" 2>/dev/null || true
            rm -f "$_BRIDGE_SOCKET" 2>/dev/null || true
        fi
    fi
}

# ─── _wsl_bridge_ensure ──────────────────────────────────────────────────────
# Idempotent bridge start. Non-fatal — always exits 0.
# - Non-WSL: no-op
# - Missing deps: log hint, exit 0
# - Already running: skip, exit 0
# - Not running: clean stale state, start bridge, write PID file
_wsl_bridge_ensure() {
    # Non-WSL: nothing to do
    if ! _is_wsl; then
        return 0
    fi

    # Get npiperelay.exe path (required for deps check and bridge start)
    local _npiperelay_path
    _npiperelay_path=$(_wsl_bridge_get_npiperelay)

    # Missing deps: log actionable hint, exit 0 (non-fatal)
    if [ -z "$_npiperelay_path" ] || ! command -v socat &>/dev/null; then
        echo "[open-chad-discord] WSL bridge: missing deps (socat and/or npiperelay.exe not found)" >&2
        echo "[open-chad-discord] Install: sudo apt install socat" >&2
        echo "[open-chad-discord] Install: GOOS=windows GOARCH=amd64 go install github.com/jstarks/npiperelay@latest" >&2
        echo "[open-chad-discord] Then add to PATH: ln -sf \"\$(go env GOPATH)/bin/windows_amd64/npiperelay.exe\" \"\$(go env GOPATH)/bin/npiperelay.exe\"" >&2
        return 0
    fi

    # Already running: skip
    if _wsl_bridge_pid_alive; then
        echo "[open-chad-discord] WSL bridge: already running (PID $(cat "$_BRIDGE_PID_FILE" 2>/dev/null))" >&2
        return 0
    fi

    # Atomic singleton lock — prevent duplicate starts under concurrent launches
    if ! mkdir "$_BRIDGE_LOCK_DIR" 2>/dev/null; then
        echo "[open-chad-discord] WSL bridge: start already in progress" >&2
        return 0
    fi

    # Clean up stale PID/socket from previous run
    _wsl_bridge_cleanup_stale

    # Remove stale socket if it exists (socat won't bind to an existing socket)
    rm -f "$_BRIDGE_SOCKET" 2>/dev/null || true

    # Ensure log file exists with secure permissions
    if [ ! -f "$_BRIDGE_LOG" ]; then
        install -m 0600 /dev/null "$_BRIDGE_LOG" 2>/dev/null || {
            touch "$_BRIDGE_LOG" 2>/dev/null || true
            chmod 0600 "$_BRIDGE_LOG" 2>/dev/null || true
        }
    fi

    # Start bridge: socat listens on Unix socket, forks npiperelay.exe per connection
    nohup socat \
        UNIX-LISTEN:"$_BRIDGE_SOCKET",fork \
        EXEC:"$_npiperelay_path -ei -s $_BRIDGE_PIPE",nofork \
        >>"$_BRIDGE_LOG" 2>&1 &
    local bridge_pid=$!

    # Write PID file
    echo "$bridge_pid" > "$_BRIDGE_PID_FILE"

    # Remove lock after brief delay (same pattern as metrics/Vision)
    (sleep 1; rmdir "$_BRIDGE_LOCK_DIR" 2>/dev/null || true) &

    echo "[open-chad-discord] WSL bridge started (PID $bridge_pid, socket $_BRIDGE_SOCKET)" >&2
    return 0
}

# ─── _wsl_bridge_stop ────────────────────────────────────────────────────────
# Stop the bridge and clean up PID file and socket.
_wsl_bridge_stop() {
    if [ -f "$_BRIDGE_PID_FILE" ]; then
        local pid
        pid=$(cat "$_BRIDGE_PID_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "[open-chad-discord] WSL bridge stopped (PID $pid)" >&2
        fi
        rm -f "$_BRIDGE_PID_FILE" 2>/dev/null || true
    fi
    rm -f "$_BRIDGE_SOCKET" 2>/dev/null || true
    rmdir "$_BRIDGE_LOCK_DIR" 2>/dev/null || true
}
