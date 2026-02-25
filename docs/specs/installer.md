# Installer

> **Version:** 1.0.0
> **Updated:** 2026-02-25

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
