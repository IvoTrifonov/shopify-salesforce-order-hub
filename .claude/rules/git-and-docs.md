# Git and documentation

## Git

- Do not commit or push unless the user asks. When work is finished, propose a
  commit message instead.
- Commit messages: imperative subject line under ~50 characters, a blank line,
  then a short bullet list of the changes. Explain _why_ when it is not obvious.
- Before committing, files must pass `npm run prettier:verify` (CI enforces
  it). Run `npm run prettier` to fix them; the pre-commit hook only formats
  staged files.
- Work on a branch and merge to `main` through a pull request, so CI validates
  the change before it is deployed.
- When proposing a commit for a significant change (a new area, pattern,
  workflow or changed environment, not routine metadata, bug fixes or small UI
  changes), also run the `review-claude-config` skill. Suggest `.claude/`
  updates only if it finds something worth updating; otherwise say nothing
  about it.

## Documentation

- Significant design decisions get an ADR in `docs/decisions/`, numbered
  sequentially (`0003-<topic>.md`), with Context, Decision and Consequences.
- When a roadmap item is finished, tick it in `README.md`, and update the
  README's architecture, data model and diagrams if the change affects them.
- The README describes the project only; it does not mention why the project
  was built or who it is for.
