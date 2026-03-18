# Criteria Prioritizer

When facing a decision with meaningful tradeoffs — architecture choices, refactors, "which approach?" questions — use the `prioritizer` sub-agent to draft context-aware criteria questions, then present them to the user via the `question` tool.

## When to Trigger

Use the criteria prioritizer when **all** of these are true:

1. There are 2+ viable approaches that differ on real tradeoffs
2. The "best" answer depends on what the user values most
3. You haven't already been told the priorities in this session

**Skip it** when:
- The user gave explicit constraints ("make it fast", "keep it simple")
- There's only one reasonable approach
- The decision is trivial or easily reversible
- You already collected priorities earlier in this conversation

### Strong Skip Rule

Do **not** invoke the prioritizer for every choice. Use it only when the answer would materially change based on user values.

Skip immediately for:
- Straight bug fixes where the correct repair is obvious
- Mechanical migrations, renames, formatting, or lint cleanup
- Small implementation details inside an already-chosen approach
- Decisions already constrained by security, API compatibility, or existing architecture

Use it when changing the user's priorities would likely change the recommendation.

## How It Works

### Step 1: Spawn the Prioritizer Sub-Agent

Use the `task` tool to spawn the `prioritizer` sub-agent. Pass it:
- **The decision**: what approaches you're considering and why
- **The domain**: what area of the codebase this affects
- **Key files**: relevant files or modules (if known)

### Context Packing Rules

Keep the sub-agent prompt compact but concrete. Include:
- The 2-3 candidate approaches you are actually weighing
- The reason this is a real tradeoff, not a routine decision
- Up to 5 high-signal file paths or symbols
- Any known hard constraints already present in the repo or user request

Do **not** dump the whole conversation or large file contents into the sub-agent prompt. Let the sub-agent read what it needs.

Example task prompt:
```
I need to decide between three auth approaches for our SvelteKit app:
A) Server-side sessions with Redis
B) JWT with httpOnly cookies
C) OAuth delegation to Auth.js

Domain: Authentication for src/routes/(protected)/
Key files: src/hooks.server.ts, src/lib/auth/

Analyze the codebase context and tradeoff space, then draft context-specific
criteria questions following the prioritizer output format.
```

Canonical `task` example:
```json
{
  "subagent_type": "prioritizer",
  "description": "Draft auth tradeoff criteria",
  "prompt": "Decision: choose between server-side Redis sessions, JWT cookies, and Auth.js delegation for protected SvelteKit routes. Domain: authentication for src/routes/(protected)/. Key files: src/hooks.server.ts, src/lib/auth/, src/routes/login/+page.server.ts. Real tradeoff: operational simplicity vs long-term extensibility vs third-party dependency surface. Draft context-specific criteria questions and a decision map following the prioritizer output format."
}
```

The sub-agent will:
1. Scan the relevant code to understand existing patterns and constraints
2. Research the tradeoff space for the specific domain
3. Return a structured block containing:
   - **Context summary** — what it found
   - **Approaches identified** — with key tradeoffs
   - **Criteria questions JSON** — ready to pass to the question tool
   - **Decision map** — how each criterion maps to an approach

### Step 2: Present Questions to the User

Extract the `questions` JSON from the sub-agent's response and pass it directly to the `question` tool. The questions will be context-specific — referencing the actual approaches, codebase patterns, and domain tradeoffs rather than generic criteria.

Ask the drafted questions with minimal paraphrasing. Only rewrite them if the sub-agent produced awkward wording or exceeded the question tool's practical limits.

### Step 3: Interpret and Apply

After collecting the user's answers:

1. **Restate the priorities** in a short block before your recommendation:
   ```
   Your priorities: Type safety=High, Migration effort=Critical, Bundle size=Medium, DX=High
   Hard constraint: Must work with existing Drizzle schema
   ```

2. **Use the decision map** from the sub-agent to identify the winning approach

3. **Name the winning approach** and explain why it wins under these priorities

4. **Name what you're sacrificing** — be explicit about what a different priority set would have chosen instead

5. **Carry the priorities forward** — apply them to all subsequent decisions in this session unless the user changes them

### Recommended Result Format

After the user answers, prefer this structure:

```
Your priorities: {Criterion A=Level, Criterion B=Level, Criterion C=Level, Criterion D=Level}
Hard constraint: {constraint}

Recommendation: {winning approach}

Why this wins:
- {reason tied directly to priority 1}
- {reason tied directly to priority 2}

Tradeoff accepted:
- {what loses because of the chosen priorities}
```

## Fallback: Generic Criteria

If the `prioritizer` sub-agent is unavailable or the decision is simple enough that spawning a sub-agent is overkill, use these default criteria directly with the `question` tool:

| Criterion | What it captures |
|-----------|-----------------|
| **Correctness** | Edge-case coverage, reliability, error handling |
| **Simplicity** | Implementation clarity, cognitive load, LOC |
| **Speed to ship** | Time to working solution, iteration speed |
| **Maintainability** | Future readability, extensibility, refactor cost |

### Fallback Scale

| Level | Label | Meaning |
|-------|-------|---------|
| 4 | `Critical` | Optimize for this even at significant cost elsewhere |
| 3 | `High` | Strong preference — weight heavily |
| 2 | `Medium` | Balance with other concerns |
| 1 | `Low` | Mostly ignore unless free |

### Fallback Question Format

```json
{
  "questions": [
    {
      "header": "Correctness",
      "question": "How important is correctness and edge-case coverage?",
      "options": [
        { "label": "Critical", "description": "Most reliable option, even if slower or more complex" },
        { "label": "High", "description": "Reliability strongly matters" },
        { "label": "Medium", "description": "Balance with other concerns" },
        { "label": "Low", "description": "Good enough is fine" }
      ]
    },
    {
      "header": "Simplicity",
      "question": "How important is implementation simplicity?",
      "options": [
        { "label": "Critical", "description": "Simplest solution, even if less optimized" },
        { "label": "High", "description": "Keep things straightforward" },
        { "label": "Medium", "description": "Nice to have" },
        { "label": "Low", "description": "Complexity is acceptable if it pays off" }
      ]
    },
    {
      "header": "Speed to ship",
      "question": "How important is shipping quickly?",
      "options": [
        { "label": "Critical", "description": "Time is the main driver" },
        { "label": "High", "description": "Prefer faster delivery" },
        { "label": "Medium", "description": "Balanced with quality" },
        { "label": "Low", "description": "No rush, do it right" }
      ]
    },
    {
      "header": "Maintainability",
      "question": "How important is long-term maintainability?",
      "options": [
        { "label": "Critical", "description": "Optimize for future clarity and extensibility" },
        { "label": "High", "description": "Strong long-term bias" },
        { "label": "Medium", "description": "Balanced concern" },
        { "label": "Low", "description": "Short-term solution is acceptable" }
      ]
    },
    {
      "header": "Constraints",
      "question": "Any hard constraint that overrides these priorities?",
      "options": [
        { "label": "None", "description": "Use the priorities above as-is" },
        { "label": "Match existing patterns", "description": "Stay consistent with current codebase conventions" },
        { "label": "Minimize dependencies", "description": "Avoid adding new libraries or services" },
        { "label": "Must be reversible", "description": "Needs to be easy to undo or swap out later" }
      ]
    }
  ]
}
```

## Tie-Breaking

When two approaches score equally under the stated priorities:
- Ask a single follow-up: "Which single factor should break ties?"
- Do NOT re-run the full prioritizer

## Priority Memory

Once collected, priorities persist for the session. Reference them when making later decisions:
```
Based on your earlier priorities (Simplicity=Critical), I'm choosing X over Y here.
```

If the task domain shifts significantly (e.g., from backend API to frontend UI), ask:
```
Your priorities were set for backend work. Should I re-evaluate for this UI task, or keep the same weights?
```
