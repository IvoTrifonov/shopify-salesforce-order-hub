---
name: review-claude-config
description: Check whether the .claude configuration (CLAUDE.md, rules, skills) still matches the codebase after significant changes, and propose targeted updates. Use when proposing a commit for a significant change, after the user commits a larger feature, or when the user asks to review the Claude configuration.
---

# Review the Claude configuration

The configuration only earns an update when a change alters what a future
session needs to know. Most changes do not.

```sh
node .claude/skills/review-claude-config/review.js
```

The script reviews everything since the last commit that touched `.claude/`
(plus uncommitted work) and reports:

- the commits and changed files in that range, grouped by kind;
- **new components** (classes, triggers, objects, events, LWC, flows, CI…);
- **drift**: project classes, triggers and objects not mentioned anywhere in
  `.claude/`, and names mentioned in `.claude/` that no longer exist.

Arguments given by the user: $ARGUMENTS

## Deciding whether an update is worth it

Worth an update:

- A new area of the system or a new architectural piece (e.g. outbound sync,
  a batch layer, a new Platform Event, CI/CD), so the code map in
  `.claude/CLAUDE.md` is incomplete.
- A new convention or pattern the code now follows and future work should
  repeat (e.g. a callout framework, a selector layer, a retry strategy).
- A new recurring workflow done by hand more than once: a candidate skill.
- Changed environment or commands: new org, new scripts, new deployment steps.
- A rule that turned out wrong, outdated or repeatedly corrected by the user.
- Names in `.claude/` that no longer exist (stale references mislead).

Not worth an update:

- New fields or other metadata within an existing area, bug fixes, tests,
  refactoring within a class, small LWC or UI changes, README or ADR edits.
- Drift entries for helpers that are obvious from their area (e.g. a test
  data class next to a listed service). Mention only what a newcomer would
  need to find.

## Steps

1. Run the script and read the report.
2. Decide using the criteria above. If nothing qualifies, say so in one line
   and stop.
3. Otherwise propose the concrete edits: which file, what to add, change or
   remove, and why, in a short list. Keep `.claude/CLAUDE.md` a compact map;
   detailed guidance belongs in a `rules/` file.
4. Apply the edits only after the user approves them, then suggest a commit
   message (e.g. `Update Claude configuration for outbound sync`).
