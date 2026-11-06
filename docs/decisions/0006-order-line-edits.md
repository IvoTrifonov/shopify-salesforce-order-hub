# 6. Sync order edits to order lines

**Status:** Accepted

## Context

[ADR 0005](0005-inbound-order-updates.md) applied `orders/updated` to the
order header only and left the lines as they were when the order was
created. After an order edit or cancellation, `Order.TotalAmount` (the sum of
the OrderItems) no longer matched Shopify's current total.

Real deliveries from the dev store and Shopify's documentation showed that:

- `orders/updated` carries the full order after the edit. A line's
  `current_quantity` holds its quantity after edits and cancellations; a
  removed or cancelled line stays in `line_items` with `current_quantity` 0.
  A product added by an edit appears as a new line with a new line ID.
- A removed shipping line stays in `shipping_lines` with `is_removed: true`.
- `orders/edited` reports only the changes (quantity deltas), not the
  resulting order.
- `orders/updated` can arrive before `orders/create`, so the first version
  Salesforce sees of an order may already be edited or cancelled.

On the Salesforce side, an order product cannot have quantity 0
(`FIELD_INTEGRITY_EXCEPTION`), and an activated order locks its OrderItems.
Setting the order back to Draft to change them is ruled out: inbound sync
never writes `Order.Status` (ADR 0005).

## Decision

- **Reconcile the lines with Shopify's current lines** for every version that
  is applied, new orders included. `ShopifyOrderLineSync` compares the
  payload with the stored OrderItems by `Shopify_Line_Item_Id__c`: a current
  line without an OrderItem is inserted, a changed quantity or price is
  updated, and a line Shopify removed (`current_quantity` 0, `is_removed`) is
  deleted. Only differences are written, so replaying a log changes nothing.
- **Use `orders/updated`, not `orders/edited`.** A full snapshot can be
  applied any number of times and in any order with the same result; deltas
  cannot.
- **Leave OrderItems without a Shopify line ID alone.** They were added in
  Salesforce.
- **Do not change the lines of an activated order.** Its header is updated as
  before, and `Order.Lines_Out_Of_Sync__c` is set while its lines differ from
  Shopify's; the sync log is `Success` with a note. The flag clears once the
  lines match again: after the order is set back to Draft, replaying its
  latest log applies the lines.
- Lines are planned before the header is upserted (the flag is part of the
  header) and written after it (new orders need their Order ID first). The
  line logic, including products and price book entries, moved from
  `ShopifyOrderService` to `ShopifyOrderLineSync`.

## Consequences

- `Order.TotalAmount` matches `Shopify_Total_Price__c` after edits and
  cancellations, as long as the order has no discounts or taxes, which are
  not stored on lines. This restores the
  [ADR 0002](0002-asynchronous-webhook-processing.md) consequence that ADR
  0005 had suspended.
- A cancelled Draft order has no OrderItems left. `refunds/create` refers to
  line IDs that may no longer have an OrderItem and must not depend on them.
- An edit of a paid order does not change its invoice; invoice changes come
  with `refunds/create` (ADR 0005).
- Processing a batch costs one more query (the stored OrderItems) and up to
  two more DML statements (update and delete), independent of its size.
