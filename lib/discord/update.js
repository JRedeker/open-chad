#!/usr/bin/env node
// lib/discord/update.js — Short-lived Discord Rich Presence updater
//
// Usage: node lib/discord/update.js <session_count> <elapsed_seconds> <tagline>
//
// Connects to Discord via IPC, sends one SET_ACTIVITY update, then exits.
// No persistent process. Rate limiting is handled by the calling update.sh.
//
// Environment:
//   DISCORD_CLIENT_ID   — Discord application client ID (17-20 digit number)
//   OPEN_CHAD_DEBUG     — Set to '1' to enable verbose debug logging
//
// Exit codes:
//   0 — Success or Discord not running (graceful skip)
//   1 — Fatal error (misconfiguration, invalid args)

'use strict';

const path = require('path');
const os = require('os');
const fs = require('fs');

// ─── Logging ────────────────────────────────────────────────────────────────

// Use OPEN_CHAD_CACHE_DIR (user-private, set by opencode_env.sh) when available,
// falling back to os.tmpdir() for environments where the cache dir is not set.
const LOG_FILE = process.env.OPEN_CHAD_CACHE_DIR
  ? path.join(process.env.OPEN_CHAD_CACHE_DIR, 'discord.log')
  : path.join(os.tmpdir(), 'open-chad-discord.log');
const DEBUG = process.env.OPEN_CHAD_DEBUG === '1';

function log(level, message, data) {
  const ts = new Date().toISOString();
  const entry = {
    ts,
    level,
    message,
    ...(data ? { data } : {}),
  };
  const line = JSON.stringify(entry) + '\n';
  try {
    fs.appendFileSync(LOG_FILE, line);
  } catch (_) {
    // Log write failure is non-fatal
  }
  if (DEBUG) {
    process.stderr.write(`[open-chad-discord] ${level.toUpperCase()} ${message}\n`);
  }
}

// ─── Sanitizer ──────────────────────────────────────────────────────────────
// Defense-in-depth: strip any sensitive patterns before any Discord API call.
// Exported for testing via discord_sanitizer_test.sh.

const SANITIZE_PATTERNS = [
  // Home directory paths: /home/user/..., /Users/user/..., ~/..., /root/...
  { pattern: /\/home\/[^/\s]+[^\s]*/g, label: 'linux-home-path' },
  { pattern: /\/Users\/[^/\s]+[^\s]*/g, label: 'macos-home-path' },
  { pattern: /~\/[^\s]*/g, label: 'tilde-path' },
  { pattern: /\/root\/[^\s]*/g, label: 'root-path' },
  // Named environment variables: ${VAR} or $VAR_NAME (uppercase, underscore-separated)
  { pattern: /\$\{[A-Za-z_][A-Za-z0-9_]*\}/g, label: 'env-var-brace' },
  { pattern: /\$[A-Z_][A-Z0-9_]{2,}/g, label: 'env-var-bare' },
  // Common token prefixes
  { pattern: /sk-[A-Za-z0-9_-]{16,}/g, label: 'sk-token' },
  { pattern: /gh[pous]_[A-Za-z0-9]{20,}/g, label: 'github-token' },
  { pattern: /AKIA[A-Z0-9]{16}/g, label: 'aws-access-key' },
  // Long opaque alphanumeric strings (20+ chars) that look like tokens
  { pattern: /\b[A-Za-z0-9]{20,}\b/g, label: 'long-token' },
];

/**
 * Sanitize a string by replacing known-sensitive patterns with [REDACTED].
 * Safe strings (taglines, elapsed time, session counts) pass through unchanged.
 * @param {string} input
 * @returns {string}
 */
function sanitize(input) {
  if (typeof input !== 'string') return '';
  let result = input;
  for (const { pattern, label } of SANITIZE_PATTERNS) {
    const before = result;
    result = result.replace(pattern, '[REDACTED]');
    if (result !== before && DEBUG) {
      log('debug', `sanitizer: redacted ${label}`, { before, after: result });
    }
  }
  return result;
}

// ─── GitHub repo button URL ──────────────────────────────────────────────────

const GITHUB_REPO_URL = 'https://github.com/JRedeker/open-chad';
const LARGE_IMAGE_KEY = 'open_chad_logo';
const LARGE_IMAGE_TEXT = 'open-chad — AI session orchestrator';
const CONNECT_TIMEOUT_MS = 8000;
const PRESENCE_HOLD_SEC = Math.max(0, parseInt(process.env.OPEN_CHAD_DISCORD_HOLD_SEC || '0', 10) || 0);

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const clientId = process.env.DISCORD_CLIENT_ID;
  if (!clientId) {
    log('error', 'DISCORD_CLIENT_ID is not set');
    process.exit(1);
  }
  if (!/^\d{17,20}$/.test(clientId)) {
    log('error', 'DISCORD_CLIENT_ID format invalid — must be 17-20 digits', { clientId });
    process.exit(1);
  }

  // Args: session_count elapsed_seconds tagline
  const sessionCount = parseInt(process.argv[2] || '1', 10);
  const elapsedSeconds = parseInt(process.argv[3] || '0', 10);
  const taglineRaw = process.argv[4] || 'Chadding hard';

  // Sanitize all dynamic inputs before use
  const tagline = sanitize(taglineRaw);
  const sessionLabel = `${sessionCount} session${sessionCount !== 1 ? 's' : ''}`;

  // Format elapsed time
  const hours = Math.floor(elapsedSeconds / 3600);
  const minutes = Math.floor((elapsedSeconds % 3600) / 60);
  const elapsedStr = hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;

  log('info', 'discord update starting', {
    sessionCount,
    elapsedSeconds,
    tagline,
  });

  let client;
  try {
    const { Client } = require('@xhayper/discord-rpc');
    client = new Client({ clientId });
  } catch (err) {
    log('error', 'failed to require @xhayper/discord-rpc', { message: err.message });
    process.exit(0); // Non-fatal — Discord lib unavailable, skip silently
  }

  // Connect with timeout — Discord desktop may not be running
  let connectTimeout;
  const connectPromise = new Promise((resolve, reject) => {
    connectTimeout = setTimeout(() => {
      reject(new Error('connection timeout'));
    }, CONNECT_TIMEOUT_MS);

    client.on('ready', () => {
      clearTimeout(connectTimeout);
      resolve();
    });

    client.on('error', (err) => {
      clearTimeout(connectTimeout);
      reject(err);
    });

    client.login().catch(reject);
  });

  try {
    await connectPromise;
  } catch (err) {
    log('info', 'discord not reachable — skipping update (non-fatal)', {
      reason: err.message,
    });
    process.exit(0); // Discord not running — silent skip per SC-10
  }

  log('info', 'discord connected, sending presence update');

  try {
    await client.user.setActivity({
      details: tagline,
      state: `${sessionLabel} · ${elapsedStr} elapsed`,
      largeImageKey: LARGE_IMAGE_KEY,
      largeImageText: LARGE_IMAGE_TEXT,
      startTimestamp: new Date(Date.now() - elapsedSeconds * 1000),
      buttons: [
        {
          label: 'View on GitHub',
          url: GITHUB_REPO_URL,
        },
      ],
    });
    log('info', 'presence update sent successfully', {
      details: tagline,
      state: `${sessionLabel} · ${elapsedStr} elapsed`,
    });

    // Keep the RPC connection alive when explicitly requested.
    // Rich Presence is tied to the IPC connection and is cleared on disconnect.
    if (PRESENCE_HOLD_SEC > 0) {
      log('info', 'holding presence connection', { holdSeconds: PRESENCE_HOLD_SEC });
      await new Promise((resolve) => setTimeout(resolve, PRESENCE_HOLD_SEC * 1000));
    }
  } catch (err) {
    log('warn', 'failed to set activity', { message: err.message });
    // Non-fatal — Discord running but activity update failed
  } finally {
    try {
      client.destroy();
    } catch (_) {
      // Ignore destroy errors
    }
  }

  process.exit(0);
}

// ─── Module exports (for testing) ───────────────────────────────────────────

if (require.main === module) {
  main().catch((err) => {
    log('error', 'unhandled error in main', { message: err.message, stack: err.stack });
    process.exit(0); // Always exit 0 to be non-fatal to open-chad
  });
}

module.exports = { sanitize };
