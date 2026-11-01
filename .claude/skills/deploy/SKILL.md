---
name: deploy
description: Deploy this project's metadata to the orderhub org and report test results and code coverage. Use whenever metadata or Apex in force-app needs to be deployed, validated (dry run) or tested in the org.
---

# Deploy to orderhub

Run the deploy script from the project root. It always targets `orderhub`,
deploys with `--source-dir`, and prints a summary: status, component failures,
test failures with their first stack line, and coverage for this project's
classes (anything under 90% is flagged).

```sh
node .claude/skills/deploy/deploy.js [options]
```

| Option | Effect |
|---|---|
| *(none)* | Deploy `force-app` and run all local tests (`RunLocalTests`) |
| `--dry-run` | Validate only; nothing is saved in the org |
| `--tests A,B` | Run only the given test classes (`RunSpecifiedTests`), for quick iterations |
| `--no-tests` | Skip tests; only for metadata without Apex (`NoTestRun`) |
| `--path <dir>` | Deploy a sub-folder instead of `force-app` |

Arguments given by the user: $ARGUMENTS

## Steps

1. Choose options from the user's request. Default to all local tests; use
   `--dry-run` first for risky changes (deletions, field type changes,
   permission changes).
2. Run the script. It exits with code 1 if the deploy or any test fails.
3. On failure, fix the cause and run it again. Do not retry unchanged.
4. Report the outcome plainly: what was deployed, tests passed/total, coverage
   of the changed classes, and anything flagged.
