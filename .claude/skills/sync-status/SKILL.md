---
name: sync-status
description: Inspect Shopify sync activity in the orderhub org (recent Sync_Log__c entries with their Orders and Invoices, details of one log) and replay a stored webhook through the processor. Use when checking whether webhooks arrived, debugging a failed sync, or reprocessing an order.
---

# Sync status and replay

```sh
node .claude/skills/sync-status/sync-status.js list [--limit N] [--status Error|Pending|Success|Skipped]
node .claude/skills/sync-status/sync-status.js show LOG-000004
node .claude/skills/sync-status/sync-status.js replay LOG-000004
```

| Command  | Shows / does                                                                                                                                                   |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `list`   | Latest logs (default 10): status, topic, Shopify ID, linked Order and its invoices, first line of any error                                                    |
| `show`   | One log in full: error message, payload size and key payload fields, the Order with totals, its lines and invoices                                             |
| `replay` | Sets an inbound log back to `Pending` and publishes `Shopify_Webhook__e`, exactly as the endpoint does, then waits for the processor and prints the new status |

Arguments given by the user: $ARGUMENTS

## Steps

1. Start with `list` unless the user named a log; use `--status Error` to find
   failures.
2. Use `show` to explain a failure: read the error, compare it with the
   payload fields, and point at the code or data that caused it.
3. `replay` reprocesses real data in the org. Only replay after the cause of a
   failure is fixed and deployed, or when the user asks for it. Upserts are
   idempotent, so replaying a successful log updates the same records.
4. Report what was found in plain words; for a replay, report the new status
   and the resulting Order and invoice.
