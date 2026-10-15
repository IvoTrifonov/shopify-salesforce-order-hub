# Shopify → Salesforce Order Hub

Bi-directional, event-driven integration between a real [Shopify](https://www.shopify.com/)
storefront and Salesforce. Shopify acts as the system of record for orders;
Salesforce serves as the back office where orders are processed, invoiced,
monitored and reconciled.

This is a custom order hub built on the standard `Order` / `OrderItem`
objects. It deliberately does not use the
[Salesforce Order Management](https://www.salesforce.com/commerce/order-management/)
product, so that the integration, async processing and UI are written by hand
on the core platform.

> See the [roadmap](#roadmap) for current status.

## Architecture

**Inbound (Shopify → Salesforce).** Shopify webhooks (`orders/create`,
`orders/updated`, `refunds/create`) call a public Apex REST endpoint exposed
through a Salesforce Site. The endpoint verifies the
`X-Shopify-Hmac-Sha256` signature, parses the payload and upserts records
using the Shopify order ID as an external ID, making the operation
idempotent. Out-of-order deliveries are ignored by comparing the payload's
`updated_at` with `Order.Shopify_Updated_At__c`. A trigger framework (one
trigger per object, handler pattern) creates invoices, links or creates
Accounts/Contacts by customer email, and writes a sync log entry.

**Outbound (Salesforce → Shopify).** When an order status changes in
Salesforce, the Order trigger publishes an `Order_Status_Changed__e`
Platform Event. A subscriber trigger on the event enqueues a Queueable job,
which calls the Shopify GraphQL Admin API through a Named Credential.
Decoupling through Platform Events keeps the user's transaction free of
callouts and lets other subscribers react to the same event. Failed callouts
are retried via chained Queueables up to a configurable limit, then surfaced
in the UI for manual retry.

**Batch layer.** A nightly Batch Apex job reconciles the last 24 hours of
Shopify orders against Salesforce and logs discrepancies. A second batch
detects duplicate customer Accounts and flags merge candidates. Scheduled
Apex orchestrates both.

**UI.** Lightning Web Components: a sync-monitoring dashboard, a failed-sync
list with one-click retry, and a duplicate-review component.

**Configuration.** Runtime settings (retry limits, API version, feature
toggles) live in Custom Metadata Types, so behaviour can change without a
code deployment. Secrets such as the webhook signing key and the Admin API
token are kept in Named / External Credentials, never in code or metadata
records.

## Data model

| Object | Purpose | Key fields |
|---|---|---|
| `Order` (standard) | Shopify order header | `Shopify_Order_Id__c` (external ID), `Financial_Status__c`, `Shopify_Fulfillment_Status__c`, `Shopify_Total_Price__c`, `Customer_Email__c`, `Shopify_Updated_At__c` |
| `OrderItem` (standard) | Order line | `Shopify_Line_Item_Id__c` (external ID), `Variant_Title__c` |
| `Product2` (standard) | Product variant | `Shopify_Product_Id__c`, `Shopify_Variant_Id__c` (external ID) |
| `Invoice__c` | Invoice generated from an order | `Order__c` |
| `Sync_Log__c` | Audit trail of every inbound/outbound sync | `Direction__c`, `Status__c`, `Event_Topic__c`, `HTTP_Status_Code__c`, `Retry_Count__c`, `Payload__c`, `Error_Message__c` |
| `Order_Status_Changed__e` | Platform Event driving outbound sync | — |

## Engineering standards

- **Testing.** Every class is covered by meaningful tests, not just for
  coverage: bulk tests (200 records), negative paths, and `HttpCalloutMock`
  for every callout.
- **Bulkification.** All triggers and services are written for bulk input
  and stay within governor limits.
- **Security.** Classes declare `with sharing` unless there is a documented
  reason not to; CRUD/FLS is enforced (`WITH USER_MODE` / `Security.stripInaccessible`).
  The public Site guest user has the minimum permissions needed to call the
  webhook endpoint, and every request is rejected unless its HMAC signature
  is valid.
- **Design decisions.** Significant decisions and their trade-offs are
  recorded in [`docs/`](docs/).

## Roadmap

The first milestone is a thin end-to-end slice. Later items add breadth on
top of that working path.

**Milestone 1: end-to-end slice**

- [x] SFDX project scaffold
- [ ] Data model (standard `Order` / `OrderItem` / `Product2` + `Invoice__c`, `Sync_Log__c`)
- [ ] Trigger framework
- [ ] Inbound webhook endpoint with HMAC verification (`orders/create`)
- [ ] CI/CD pipeline (deploy validation + Apex tests on every PR)

**Milestone 2: full sync**

- [ ] `orders/updated` and `refunds/create` webhooks with out-of-order handling
- [ ] Invoice generation and Account/Contact matching
- [ ] Outbound fulfillment sync (Platform Event → Queueable → GraphQL Admin API, with retry)
- [ ] Custom Metadata configuration

**Milestone 3: back office**

- [ ] Nightly reconciliation batch
- [ ] Customer deduplication batch
- [ ] LWC sync dashboard, failed-sync retry and duplicate review
- [ ] Demo video / GIF in this README

## Tech stack

Apex · Trigger framework · Platform Events · Asynchronous Apex (Queueable /
Batch / Scheduled) · Inbound REST (`@RestResource` + HMAC verification) ·
Shopify GraphQL Admin API via Named Credentials · Custom Metadata Types ·
Lightning Web Components · SFDX · GitHub Actions CI/CD

## Project structure

- `force-app/main/default/` — metadata source (classes, triggers, objects, LWC)
- `manifest/` — `package.xml` deployment manifest
- `config/` — scratch org definitions
- `scripts/` — automation scripts
- `docs/` — design decisions and architecture documentation

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
