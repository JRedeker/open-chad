# LBP — Long-Term Best Practice

The user's default stance is **long-term best practice** for all decisions unless they explicitly say otherwise. This means:

- When choosing between approaches, prefer the one that would be chosen for a **greenfield project with no legacy constraints**.
- Prefer **current, well-maintained, widely-adopted** solutions over legacy patterns that "still work."
- Prefer **official recommendations** from framework/library authors over community workarounds.
- When in doubt, research before committing — use Context7, official docs, and grep.app to verify that the approach aligns with where the ecosystem is heading, not where it's been.

## When the user says "lbp?"

This is a request to **stop and research**. Before proceeding:

1. **Research the current best practice** — Use Context7 to check official documentation for the library/framework in question.
2. **Compare with what we're doing** — Is our current approach aligned with the recommended path, or are we using a legacy/deprecated pattern?
3. **Check the greenfield question** — "If we were starting from scratch today, with no existing code to be compatible with, what would we choose?"
4. **Report findings** — Present what you found with sources. If our approach is already best practice, confirm it. If not, recommend the change.

## Examples

- Choosing between REST and tRPC for a new TypeScript API? Research what the ecosystem recommends today, not what was standard 3 years ago.
- Picking a state management library? Check what the framework authors currently recommend, not what has the most Stack Overflow answers.
- Structuring a project? Look at the official starter templates and docs, not inherited conventions from older projects.

## This is a default, not a mandate

The user may choose to deviate for pragmatic reasons (compatibility, timeline, team familiarity). But the agent should always **surface the LBP option first** so the user can make an informed choice.
