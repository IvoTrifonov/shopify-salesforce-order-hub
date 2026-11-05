# 5. Sync order updates from Shopify

**Status:** Accepted

## Context

Orders change in Shopify after they are created: they are paid, fulfilled,
edited and cancelled. Shopify has no single order status; an order has a
payment state (`financial_status`), a fulfillment state
(`fulfillment_status`) and a lifecycle (`closed_at` when it is archived,
which happens on fulfillment, and `cancelled_at`).

Real `orders/updated` deliveries from the dev store showed that:

- the topic fires for every change and carries the full order, in the same
  shape as `orders/create`;
- deliveries are not ordered: an update can arrive before the `orders/create`
  of the same order, and two updates can be processed in the same batch;
- a cancellation sets `cancelled_at`, `cancel_reason` and `closed_at`, sets
  `current_total_price` to 0 (`total_price` keeps the checkout amount) and the
  lines' `current_quantity` to 0, but leaves `financial_status` unchanged;
- Shopify retries a delivery until it gets a 2xx, with the same
  `X-Shopify-Webhook-Id`.

`Order.Status` (Draft / Activated) drives the Salesforce back-office workflow
and, through `Order_Status_Changed__e`, the planned outbound sync to Shopify.
Salesforce also locks the OrderItems of an activated order.

## Decision

- Subscribe to `orders/updated` only. It covers payment, fulfillment,
  cancellation and edits, and goes through the same endpoint, processor and
  upsert as `orders/create`. The more specific topics (`orders/paid`,
  `orders/cancelled`, …) would deliver the same payload again.
- **Shopify owns the `Shopify_*` fields, Salesforce owns `Order.Status`.**
  Inbound updates never write `Order.Status`; Shopify's lifecycle goes into
  `Shopify_Order_Status__c` (open / closed / cancelled, cancelled first since
  a cancelled order is also closed), `Cancelled_At__c` and
  `Cancel_Reason__c`. Writing `Order.Status` from Shopify would publish
  `Order_Status_Changed__e` and echo the change back to Shopify.
- **Ignore outdated versions.** A payload whose `updated_at` is older than
  `Order.Shopify_Updated_At__c` is not applied; its log is marked `Skipped`
  and linked to the order. A payload with the same `updated_at` is applied
  again, which is idempotent.
- **Updates change the header only.** Lines are written when the order is
  created in Salesforce, whichever topic creates it. Syncing order edits to
  lines needs its own design because of the activated-order lock.
- `Shopify_Total_Price__c` holds `current_total_price`, the total after
  edits, refunds and cancellations.
- **Deduplicate deliveries** by storing `X-Shopify-Webhook-Id` in the unique
  `Sync_Log__c.Webhook_Id__c`. A retried delivery fails the insert with
  `DUPLICATE_VALUE` and is acknowledged with 200 without being processed
  again. The guest user gets field access to set it. The unique index does
  the check, so the guest user does not need to query or see earlier logs.
  When the endpoint fails unexpectedly, it rolls back its log
  before returning 500, so Shopify's retry is not mistaken for a duplicate.
- A cancellation does not change invoices. Invoice changes will come with
  `refunds/create`, which carries the refunded amount.

## Consequences

- A status change in Shopify is visible in Salesforce within seconds,
  including for activated orders.
- After an order edit, `Order.TotalAmount` (the sum of the lines) can differ
  from `Shopify_Total_Price__c` until order edits are synced to lines. This
  supersedes the "`TotalAmount` equals `total_price`" consequence of
  [ADR 0002](0002-asynchronous-webhook-processing.md) for edited and
  cancelled orders.
- `orders/updated` fires often, so `Sync_Log__c` grows faster; a retention
  policy belongs with the reconciliation batch.
- New Shopify picklist tokens (e.g. a new cancel reason) fail the order with
  an error log, like the existing status picklists, and are fixed by adding
  the value and replaying the log.
