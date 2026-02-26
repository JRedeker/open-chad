# Oc Launcher

> **Version:** 1.0.0
> **Updated:** 2026-02-26

## Purpose

Capability: Oc Launcher

## Requirements

### oc resolves bare project-name arguments under ~/dev with deterministic precedence

**ID:** `rq-ocLaunch1` | **Priority:** **[MUST]**

When invoked as `oc <token>`, the wrapper must preserve existing subcommand/path behavior while resolving a bare token to `~/dev/<token>` or a single `~/dev/*/<token>` match. Ambiguous nested matches must fail with a disambiguation list, and unresolved tokens must pass through unchanged.

**Tags:** `launcher`, `routing`, `safety`

#### Scenarios

**Subcommand and explicit-path precedence remain intact** (`rq-ocLaunch1.1`)

**Given:**
- `bin/oc` receives first arg `update` or `./repo`
- matching project directories may exist under ~/dev

**When:** the launcher resolves the first positional argument

**Then:**
- the first argument is forwarded unchanged
- no project-name rewrite is attempted

**Single nested match resolves with notice** (`rq-ocLaunch1.2`)

**Given:**
- `~/dev/<token>` does not exist
- exactly one `~/dev/*/<token>` directory exists

**When:** the launcher resolves bare token `<token>`

**Then:**
- argv[1] is rewritten to the matched absolute path
- a one-line resolution notice is emitted to stderr
- remaining argv is preserved

**Ambiguous nested matches fail safely** (`rq-ocLaunch1.3`)

**Given:**
- two or more `~/dev/*/<token>` directories exist

**When:** the launcher resolves bare token `<token>`

**Then:**
- launcher exits with status 1
- a disambiguation list is printed to stderr
- no automatic selection is made

---
