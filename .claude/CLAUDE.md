# Shopify → Salesforce Order Hub

Event-driven integration between a Shopify store (system of record for
orders) and Salesforce (back office: processing, invoicing, monitoring,
reconciliation). Built on the standard `Order` / `OrderItem` / `Product2`
objects. See `README.md` for the architecture, data model and roadmap, and
`docs/decisions/` for the reasoning behind major design choices.

Detailed rules live in `.claude/rules/`; follow all of them.

## Environment

- Salesforce dev org alias: **`orderhub`**. It is the only org this project
  may touch (enforced by `.claude/hooks/guard-target-org.js`).
- Shopify: a development store with an `orders/create` webhook pointing at the
  Salesforce Site endpoint `/shopify/services/apexrest/shopify/webhooks`.
- Local, untracked details (org username, store URL) are in `local-notes.md`.
- CI/CD (GitHub Actions, auth via the `SFDX_AUTH_URL` repository secret):
  every PR to `main` is validated against `orderhub`, and every merge to
  `main` that touches `force-app` deploys to `orderhub`. Anything deployed by
  hand that is not on `main` is overwritten by the next merge.

## Where things live

| Area                               | Files                                                                         |
| ---------------------------------- | ----------------------------------------------------------------------------- |
| Webhook endpoint (Site guest user) | `ShopifyWebhookResource`, `ShopifyWebhookVerifier`                            |
| Async processing (Platform Event)  | `Shopify_Webhook__e`, `ShopifyWebhookEventTrigger`, `ShopifyWebhookProcessor` |
| Order upsert                       | `ShopifyOrder` (payload DTO), `ShopifyOrderService`                           |
| Trigger framework                  | `TriggerHandler`, `OrderTrigger`, `OrderTriggerHandler`                       |
| Invoicing                          | `InvoiceService`                                                              |
| Test data                          | `ShopifyTestData`, static resource `ShopifyOrderCreateFixture`                |
| Settings                           | `Shopify_Settings__c` (protected custom setting, holds the webhook secret)    |
| Permissions                        | `Order_Hub_Admin`, `Shopify_Webhook_Guest` permission sets                    |
| CI/CD                              | `.github/workflows/` (`ci.yml`, `deploy.yml`), `.github/actions/sf-setup`     |

## Skills

Prefer these over hand-written CLI calls for the tasks they cover:

| Skill                   | Use for                                                                                 |
| ----------------------- | --------------------------------------------------------------------------------------- |
| `/deploy`               | Deploy or validate `force-app` and report tests and coverage                            |
| `/sync-status`          | Recent sync logs with their Orders and Invoices, one log in detail, replaying a webhook |
| `/capture-fixture`      | Saving a real webhook payload as an anonymized static resource for tests                |
| `/review-claude-config` | Checking whether `.claude/` still matches the codebase after significant changes        |

Their scripts share `.claude/lib/sf.js`, which always targets `orderhub`.

## MCP servers

`.mcp.json` configures the **Shopify Dev MCP** (`shopify-dev-mcp`, pinned
version, telemetry opted out, `feedback` tool denied). It has no access to
the store; it searches shopify.dev and validates code against Shopify's
schemas.

- Use `search_docs_chunks` for Shopify API and webhook questions instead of
  relying on memory; Shopify's APIs change every quarter.
- Validate every GraphQL Admin API operation with `validate` before it goes
  into Apex (call `learn_shopify_api` for the Admin API first).
- Upgrade the pinned version deliberately, after checking its release notes.

## Common commands

```sh
sf project deploy start --source-dir force-app --target-org orderhub --test-level RunLocalTests
sf project deploy start --source-dir force-app --target-org orderhub --dry-run   # validate only
sf apex run test --target-org orderhub --test-level RunLocalTests --code-coverage --wait 10
sf data query --target-org orderhub -q "SELECT Name, Status__c, Error_Message__c FROM Sync_Log__c ORDER BY CreatedDate DESC LIMIT 5"
```
