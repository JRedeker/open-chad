# Daily Repo Guidelines

## Purpose
- This repo is a single day scratch workspace created by `cds`.
- Keep it lightweight, local-first, and easy to throw away or promote.

## Expectations
- Use this repo for day-scoped experiments and notes.
- If work stabilizes or gets reused, promote it back into the parent `~/scratch` workspace structure:
  - reusable code → `src/<package_name>/`
  - standalone experiment → `experiments/<topic>/`
- Keep changes easy to understand locally. Prefer simple scripts over heavy scaffolding.

## Hygiene
- Common build artifacts are ignored via `.gitignore`.
- Do not commit secrets or bulky datasets.
- Add tests only when the scratch work is becoming reusable.
