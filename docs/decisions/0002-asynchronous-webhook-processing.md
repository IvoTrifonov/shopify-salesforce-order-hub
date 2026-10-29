# 2. Process webhooks asynchronously through a Platform Event

**Status:** Accepted

## Context

Shopify calls the webhook endpoint through a public Salesforce Site, so the
endpoint runs as the Site guest user. Salesforce enforces object permissions
for guest users even inside Apex, and guest users can be granted Create and
Read but never Edit. Upserting Orders, Accounts and Products as the guest
user is therefore impossible for updates, and granting a public user access
to customer and order data would be a poor security posture anyway.

Shopify also expects a response within five seconds and retries otherwise.

## Decision

The endpoint verifies the HMAC signature, stores the raw payload in a
`Pending` `Sync_Log__c`, publishes a `Shopify_Webhook__e` event (published
after commit) and returns 200. The guest user only needs Create on
`Sync_Log__c` and `Shopify_Webhook__e`.

A trigger on the event runs as the Automated Process user and calls
`ShopifyWebhookProcessor`, which upserts the records through
`ShopifyOrderService` and marks each log `Success` or `Error`.

Customers are modelled as a regular Account with one Contact, matched by
email. Shipping lines become OrderItems on a dedicated `Shipping` product;
discounts will follow the same approach.

## Consequences

- The guest user has no access to orders or customers.
- A failed order keeps its payload in `Sync_Log__c` and can be reprocessed
  by setting the log back to `Pending` and publishing the event again.
- Orders are upserted in bulk. If the bulk call fails, each order is retried
  on its own so one bad payload does not block the batch. The subscriber
  batch size is capped at 20 to keep that fallback within governor limits.
- `Order.TotalAmount` equals Shopify's `total_price`, so reconciliation can
  compare totals directly.
- Person Accounts are not used: enabling them is irreversible, and the
  deduplication batch is simpler with one object model.
