# Shopify → Salesforce Order Hub

Bi-directional, event-driven integration between a real [Shopify](https://www.shopify.com/)
storefront and Salesforce. Shopify acts as the system of record for orders;
Salesforce serves as the back office where orders are processed, invoiced,
monitored and reconciled.

> See the [roadmap](#roadmap) for current status.

## Architecture

**Inbound (Shopify → Salesforce).** Shopify webhooks (`orders/create`,
`orders/updated`, `refunds/create`) call a public Apex REST endpoint exposed
through a Salesforce Site. The endpoint verifies the
`X-Shopify-Hmac-Sha256` signature, parses the payload and upserts records
using the Shopify order ID as an external ID, making the operation
idempotent. A trigger framework (one trigger per object, handler pattern)
creates invoices, links or creates Accounts/Contacts by customer email, and
writes a sync log entry.

**Outbound (Salesforce → Shopify).** When an order status changes in
Salesforce, a Queueable job calls the Shopify Admin REST API through a Named
Credential. Failed callouts are retried up to three times via chained
Queueables, then surfaced in the UI for manual retry.

**Batch layer.** A nightly Batch Apex job reconciles the last 24 hours of
Shopify orders against Salesforce and logs discrepancies. A second batch
detects duplicate customer Accounts and flags merge candidates. Scheduled
Apex orchestrates both.

**UI.** Lightning Web Components: a sync-monitoring dashboard, a failed-sync
list with one-click retry, and a duplicate-review component.

## Tech stack

Apex · Trigger framework · Asynchronous Apex (Queueable / Batch / Scheduled) ·
Inbound REST (`@RestResource` + HMAC verification) · Outbound REST (Named
Credentials) · Lightning Web Components · SFDX · GitHub Actions CI/CD

## Roadmap

- [x] SFDX project scaffold
- [ ] Data model (`Order__c`, `Order_Line__c`, `Invoice__c`, `Sync_Log__c`)
- [ ] Inbound webhook endpoint with HMAC verification
- [ ] Trigger framework
- [ ] Outbound fulfillment sync (Queueable with retry)
- [ ] Nightly reconciliation batch
- [ ] Customer deduplication batch
- [ ] LWC sync dashboard
- [ ] CI/CD pipeline (deploy validation + Apex tests on every PR)

## Project structure

- `force-app/main/default/` — metadata source (classes, triggers, objects, LWC)
- `config/` — scratch org definitions
- `scripts/` — automation scripts
- `docs/` — project plan and architecture documentation

## Development

Built with the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli).
Common commands:

| Command | Purpose |
|---|---|
| `sf org login web` | Authorize an org |
| `sf project deploy start` | Deploy metadata to the org |
| `sf project retrieve start` | Retrieve metadata from the org |
| `sf apex run test` | Run Apex tests |
| `sf org open` | Open the org in a browser |

## License

[MIT](LICENSE)