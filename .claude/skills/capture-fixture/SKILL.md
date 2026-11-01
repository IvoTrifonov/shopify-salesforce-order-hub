---
name: capture-fixture
description: Turn a real Shopify webhook payload stored in a Sync_Log__c into an anonymized static resource for Apex tests. Use when a new webhook topic or a new payload shape needs realistic test data (e.g. orders/updated, refunds/create).
---

# Capture an anonymized test fixture

```sh
node .claude/skills/capture-fixture/capture-fixture.js <LOG-name> <ResourceName> [--description "..."] [--force]
```

Example: `capture-fixture.js LOG-000012 ShopifyRefundCreateFixture`

The script reads the log's payload from `orderhub`, replaces personal data
(names, emails, phones, addresses, IPs, tokens, notes, URLs) with fixed dummy
values, and writes
`force-app/main/default/staticresources/<ResourceName>.json` plus its
`.resource-meta.xml`. It then checks the output for every original personal
value and for any email outside `example.com`, and refuses to write the file if
anything is left. It never overwrites an existing fixture unless `--force` is
given.

Arguments given by the user: $ARGUMENTS

## Steps

1. Find the log with the `sync-status` skill (`list`) if the user did not
   name one. Prefer payloads from test orders in the dev store.
2. Name the resource `Shopify<Topic>Fixture` in PascalCase, e.g.
   `ShopifyOrderUpdatedFixture`.
3. Run the script and read its report. If it refuses because of leftovers,
   extend the anonymization rules in `anonymize.js` instead of editing the
   output by hand, then run it again.
4. Skim the written JSON for anything personal the rules may not know about
   (free-text notes, custom attributes) before it is committed.
5. Deploy the static resource (deploy skill) and use it from `ShopifyTestData`.
   The original payload stays only in the org's log; never save it in the repo.
