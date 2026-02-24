# open-chad: Dedicated Temp & Cache Directory Policy

## Where temp/cache files live

open-chad uses a dedicated cache directory instead of scattering files across `/tmp`.

The location is set by the `OPEN_CHAD_CACHE_DIR` environment variable, which is
resolved at startup by `lib/opencode_env.sh`:

| Condition | Resolved Path |
|-----------|---------------|
| `$XDG_RUNTIME_DIR` is set | `$XDG_RUNTIME_DIR/open-chad/` |
| `$XDG_RUNTIME_DIR` is unset (macOS, containers) | `/tmp/open-chad-$USER/` |
| `OPEN_CHAD_CACHE_DIR` is pre-set | That value is used as-is (no override) |

The directory is created with owner-only permissions (`0700`) and is guaranteed
to exist before any script that sources `opencode_env.sh` runs.

## Files in the cache directory

| File | Written by | Read by | Content |
|------|-----------|---------|---------|
| `metrics` | `collect_metrics.sh` | `status_right.sh` | `"CPU% RAM% LOAD_AVG"` |
| `zai` | `collect_metrics.sh` | `status_right.sh` | integer 0–100 or empty |
| `copilot` | `collect_metrics.sh` | `status_right.sh` | integer 0–100 or empty |
| `claude` | `collect_metrics.sh` | `status_right.sh` | integer 0–100 or empty |
| `codex` | `collect_metrics.sh` | `status_right.sh` | integer 0–100 or empty |
| `metrics.lock` | `collect_metrics.sh` | `collect_metrics.sh` | PID of running collector |

All writes are atomic: data is written to a `.$$` temp file then `mv -f`'d to
the final path to prevent partial reads.

## Cleanup

Files older than 7 days are removed from `$OPEN_CHAD_CACHE_DIR` once per
collector daemon startup (not on every launcher invocation). Active cache files
are refreshed every 30 seconds, so they are never stale when the collector runs.

## Why not `/tmp` directly?

- `/tmp` is world-writable and full of unrelated process artifacts
- Flat `/tmp/open-chad-*` names pollute the global namespace
- `$XDG_RUNTIME_DIR` is user-private (`0700`) and auto-cleaned on logout
- A single subtree can be approved once in OpenCode's file access policy

## For AI agents

When creating temporary files during a session, prefer:
- `$TMPDIR` (if set, points to a per-session safe location)
- `$(mktemp)` or `$(mktemp -d)` (respects `$TMPDIR` automatically)

Do not hardcode `/tmp/` paths when `$TMPDIR` or `$OPEN_CHAD_CACHE_DIR` are available.
