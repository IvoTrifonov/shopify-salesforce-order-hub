---
paths:
  - 'force-app/**/*.cls'
  - 'force-app/**/*.trigger'
---

# Apex conventions

## Design

- Classes are `with sharing` unless there is a reason not to; a class that is
  `without sharing` or `inherited sharing` explains why in its header comment.
- Code is bulkified: no SOQL or DML inside loops, and the number of queries and
  DML statements does not grow with the number of records.
- One trigger per object, with no logic in it. The trigger calls
  `new <Object>TriggerHandler().run()`; the handler extends `TriggerHandler`
  and overrides only the events it needs. Business logic lives in service
  classes (e.g. `InvoiceService`), not in handlers.
- Inbound Shopify data is upserted by Shopify IDs stored in external ID
  fields, so reprocessing the same payload is idempotent.
- Code running as the Site guest user only verifies, stores and publishes.
  Anything touching orders or customers runs in the Platform Event subscriber.
- Picklist values that mirror Shopify use Shopify's own tokens as API names.
- Prefer clear names over comments. Comments explain _why_, not _what_.
- New metadata uses the API version in `sfdx-project.json`.

## Tests

- Every class has a test class named `<ClassName>Test`.
- Use the `Assert` class (`Assert.areEqual`, `Assert.isTrue`, …), with a
  message when the reason for a failure would not be obvious.
- Test names describe behaviour: `invoicesOrderWhenItBecomesPaid`, not
  `testMethod1`.
- Cover the happy path, negative paths and a 200-record bulk case for any code
  that performs DML. Bulk tests assert on governor limit usage where relevant.
- Callouts are tested with `HttpCalloutMock`; Platform Event subscribers are
  tested with `Test.stopTest()` or `Test.getEventBus().deliver()`.
- Shopify payloads come from `ShopifyTestData` and its static resource
  fixtures, not hand-written JSON, unless a test needs a specific edge case.
- Aim for meaningful coverage; anything below 90% on a new class needs a
  reason.
