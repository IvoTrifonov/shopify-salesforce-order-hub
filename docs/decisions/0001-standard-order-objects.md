# 1. Use standard Order objects instead of custom ones

**Status:** Accepted

## Context

Shopify orders must be stored in Salesforce for processing, invoicing and
reconciliation. They could live in custom objects (`Order__c`,
`Order_Line__c`) or in the standard `Order`, `OrderItem` and `Product2`
objects extended with Shopify fields.

## Decision

Use the standard objects. Shopify identifiers are stored in external ID
fields (`Shopify_Order_Id__c`, `Shopify_Line_Item_Id__c`,
`Shopify_Variant_Id__c`) so inbound webhooks can upsert idempotently.

Shopify status values are stored in restricted picklists whose value API
names are Shopify's own tokens (e.g. `partially_paid`), with readable labels.
Inbound code assigns the token directly instead of maintaining a mapping.

## Consequences

- Orders work with standard reports, Account related lists, Contracts and
  the wider ecosystem without extra metadata.
- The standard objects bring constraints that inbound code must satisfy:
  an Order needs an `AccountId`, `EffectiveDate`, `Status` and `Pricebook2Id`,
  and every OrderItem needs a `PricebookEntryId`. Products and price book
  entries are therefore created on demand from the webhook payload.
- Shopify fields are optional, so records that do not come from Shopify can
  still be created in Salesforce.
- `Sync_Log__c.Order__c` uses `SetNull` on delete: the audit trail outlives
  the order it describes.
