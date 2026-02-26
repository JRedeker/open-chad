# Installer

> **Version:** 1.2.0
> **Updated:** 2026-02-26

## Purpose

Capability: Installer

## Requirements

### setup_zsh_plugins.sh installs zsh and three plugins

**ID:** `rq-zsh.1` | **Priority:** **[MUST]**

The module installs zsh via apt if absent, then clones romkatv/powerlevel10k, zsh-users/zsh-autosuggestions, and zdharma-continuum/fast-syntax-highlighting into ~/.zsh/plugins/. On subsequent runs it git-pulls each plugin instead of re-cloning.

#### Scenarios

**Clean slate install** (`sc-zsh.1.1`)

**Given:**
- zsh is not installed
- ~/.zsh/plugins/ does not exist

**When:** bash lib/setup_zsh_plugins.sh is run

**Then:**
- zsh is installed via apt
- all three plugin directories exist under ~/.zsh/plugins/
- the script exits 0

**Idempotent re-run** (`sc-zsh.1.2`)

**Given:**
- all three plugin directories already exist as git repos

**When:** bash lib/setup_zsh_plugins.sh is run a second time

**Then:**
- git pull is called on each plugin (no re-clone)
- the script exits 0
- no duplicate entries appear in ~/.zshrc

---

### Managed block in ~/.zshrc is idempotent

**ID:** `rq-zsh.2` | **Priority:** **[MUST]**

The module writes exactly one OPEN-CHAD ZSH BEGIN/END block to ~/.zshrc. Running the module N times results in exactly one block. User content outside the block is never modified.

#### Scenarios

**First run appends block** (`sc-zsh.2.1`)

**Given:**
- ~/.zshrc exists with user content
- no managed block present

**When:** bash lib/setup_zsh_plugins.sh is run

**Then:**
- ~/.zshrc contains exactly one OPEN-CHAD ZSH BEGIN/END block
- all pre-existing user content is preserved verbatim

**Second run does not duplicate block** (`sc-zsh.2.2`)

**Given:**
- ~/.zshrc already contains an OPEN-CHAD ZSH BEGIN/END block

**When:** bash lib/setup_zsh_plugins.sh is run again

**Then:**
- ~/.zshrc still contains exactly one block (count=1), not two

---

### Plugin sourcing order is correct

**ID:** `rq-zsh.3` | **Priority:** **[MUST]**

The managed block sources plugins in the order: powerlevel10k → zsh-autosuggestions → fast-syntax-highlighting. fast-syntax-highlighting must be last.

#### Scenarios

**Correct plugin order in managed block** (`sc-zsh.3.1`)

**Given:**
- setup_zsh_plugins.sh has run successfully

**When:** the OPEN-CHAD ZSH BEGIN/END block in ~/.zshrc is inspected

**Then:**
- powerlevel10k source line appears before zsh-autosuggestions
- zsh-autosuggestions appears before fast-syntax-highlighting

---

### --skip-zsh flag skips the wizard step non-interactively

**ID:** `rq-zsh.4` | **Priority:** **[MUST]**

wizard.sh accepts --skip-zsh / SKIP_ZSH=1. install.sh accepts --skip-zsh and passes it through. In --yes mode the chsh prompt is silently skipped.

#### Scenarios

**Wizard completes without hanging when --skip-zsh is set** (`sc-zsh.4.1`)

**Given:**
- wizard.sh is invoked with --yes --skip-zsh and all other --skip-* flags

**When:** the wizard runs

**Then:**
- it completes in under 10 seconds without hanging
- setup_zsh_plugins.sh is not called

---

### open-chad update re-runs setup_zsh_plugins.sh non-fatally

**ID:** `rq-zsh.5` | **Priority:** **[SHOULD]**

lib/update.sh calls setup_zsh_plugins.sh. If it fails, a warning is emitted but the update continues and exits 0.

#### Scenarios

**Update continues on zsh setup failure** (`sc-zsh.5.1`)

**Given:**
- setup_zsh_plugins.sh exits non-zero

**When:** open-chad update runs

**Then:**
- update.sh emits a WARN line
- update continues to completion with exit 0

---

### Primary launcher command is openchad with oc alias

**ID:** `rq-ocRen01` | **Priority:** **[MUST]**

Installer and update flows publish openchad as the canonical launcher while providing oc as a forwarding alias. Legacy open-chad usage must be detected and guided with migration messaging rather than silently breaking.

#### Scenarios

**Fresh install creates canonical and alias launchers** (`rq-ocRen01.1`)

**Given:**
- no existing open-chad symlinks in ~/.local/bin

**When:** install.sh is run

**Then:**
- ~/.local/bin/openchad exists and points to repo launcher
- ~/.local/bin/oc exists and forwards all args to openchad
- cds, oc-list, and oc-killall symlinks still exist

**Legacy invocation gets migration guidance** (`rq-ocRen01.2`)

**Given:**
- a user invokes open-chad after the rename

**When:** the command is executed

**Then:**
- the user receives a clear migration warning or compatibility path
- documentation and doctor output reference openchad as canonical

---

### Symlink lifecycle is centralized and consistent

**ID:** `rq-ocRen02` | **Priority:** **[MUST]**

All symlink management must be driven by a single manifest consumed by install, update, doctor, uninstall, and installer tests to prevent drift between command sets.

#### Scenarios

**Install and update use same managed symlink set** (`rq-ocRen02.1`)

**Given:**
- the managed symlink manifest is defined

**When:** install.sh and lib/update.sh are executed independently

**Then:**
- both scripts create/repair the exact same symlink names
- no command exists in one path but not the other

---

### Rename rollout is TDD-first and regression-tested

**ID:** `rq-ocRen03` | **Priority:** **[SHOULD]**

For rename and alias behavior, tests are authored before implementation changes and regression coverage spans install, update, shell profile wiring, and oc session helpers.

#### Scenarios

**Red-to-green ordering is explicit in task graph** (`rq-ocRen03.1`)

**Given:**
- implementation tasks for launcher rename and aliasing

**When:** task dependencies are inspected

**Then:**
- implementation tasks are blocked by the TDD scaffolding task
- no test task is blocked by implementation tasks

---

### setup_vision.sh registers 4 MCP servers idempotently

**ID:** `rq-vision.1` | **Priority:** **[MUST]**

setup_vision.sh verifies the vision binary is on PATH (non-fatal warn if missing), creates ~/.config/vision/servers.yaml with 0600 permissions, and registers context7 (6276), grep-app (6288), lgrep (6285), and firecrawl (6281). Running the script N times results in exactly one entry per server.

#### Scenarios

**Clean slate install** (`sc-vision.1.1`)

**Given:**
- vision binary is on PATH
- ~/.config/vision/servers.yaml does not exist

**When:** bash lib/setup_vision.sh is run

**Then:**
- ~/.config/vision/servers.yaml is created with 0600 permissions
- all 4 MCP servers are registered (context7, grep-app, lgrep, firecrawl)
- the script exits 0

**Idempotent re-run** (`sc-vision.1.2`)

**Given:**
- vision binary is on PATH
- ~/.config/vision/servers.yaml already contains all 4 servers

**When:** bash lib/setup_vision.sh is run a second time

**Then:**
- no duplicate server entries are added
- the script exits 0

**Binary missing is non-fatal** (`sc-vision.1.3`)

**Given:**
- vision binary is NOT on PATH

**When:** bash lib/setup_vision.sh is run

**Then:**
- a warning is printed mentioning vision
- the script exits 0 (non-fatal)

---

### Vision daemon starts as singleton on openchad launch

**ID:** `rq-vision.2` | **Priority:** **[MUST]**

bin/openchad starts the Vision daemon as a fire-and-forget singleton using a two-tier lock (atomic mkdir vision-start.lock + daemon self-manages PID). vision.log is created with 0600 permissions. A second concurrent openchad launch must not start a second daemon.

#### Scenarios

**First launch starts daemon** (`sc-vision.2.1`)

**Given:**
- vision binary is on PATH
- vision-start.lock does not exist
- Vision daemon is not running

**When:** openchad is launched

**Then:**
- vision-start.lock is created atomically
- vision daemon start is invoked in the background
- $OPEN_CHAD_CACHE_DIR/vision.log is created with 0600 permissions
- vision-start.lock is removed after 2 seconds

**Concurrent launch does not duplicate daemon** (`sc-vision.2.2`)

**Given:**
- vision-start.lock already exists (another launch in progress)

**When:** a second openchad is launched concurrently

**Then:**
- the second launch skips daemon start (mkdir fails)
- exactly one Vision daemon process runs

---

### openchad doctor reports Vision health

**ID:** `rq-vision.3` | **Priority:** **[MUST]**

openchad doctor checks: vision binary on PATH, vision daemon status, and all 4 MCP ports reachable via curl with a 2-second timeout. Missing binary or unreachable ports cause a non-zero exit.

#### Scenarios

**All healthy** (`sc-vision.3.1`)

**Given:**
- vision binary is on PATH
- vision daemon is running
- all 4 MCP ports respond within 2 seconds

**When:** openchad doctor is run

**Then:**
- all Vision checks pass
- the script exits 0

**Binary missing causes failure** (`sc-vision.3.2`)

**Given:**
- vision binary is NOT on PATH

**When:** openchad doctor is run

**Then:**
- doctor reports vision binary missing
- the script exits non-zero

---

### Vision daemon is stopped on uninstall

**ID:** `rq-vision.4` | **Priority:** **[MUST]**

openchad_uninstall.sh stops the Vision daemon before removing symlinks. The stop is non-fatal if Vision is not installed or not running.

#### Scenarios

**Daemon running at uninstall time** (`sc-vision.4.1`)

**Given:**
- vision binary is on PATH
- vision daemon is running

**When:** openchad uninstall is run

**Then:**
- vision daemon stop is called before symlink removal
- the script exits 0

**Binary missing is non-fatal at uninstall** (`sc-vision.4.2`)

**Given:**
- vision binary is NOT on PATH

**When:** openchad uninstall is run

**Then:**
- daemon stop is skipped gracefully
- the script exits 0

---
