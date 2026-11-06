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
- Inbound sync never writes `Order.Status` (Draft/Activated): it belongs to
  the Salesforce back office, and a change would echo back to Shopify through
  `Order_Status_Changed__e`. Shopify's state goes in the `Shopify_*` fields
  (ADR 0005).
- Code running as the Site guest user only verifies, stores and publishes.
  Anything touching orders or customers runs in the Platform Event subscriber.
- Picklist values that mirror Shopify use Shopify's own tokens as API names.
- Prefer clear names over comments. Comments explain _why_, not _what_.
- New metadata uses the API version in `sfdx-project.json`.
- Since API 67.0, SOQL, SOSL and DML run in user mode by default (CRUD and FLS
  of the running user are enforced; `WITH SECURITY_ENFORCED` is gone). Code
  run by the integration user needs every object and field it touches,
  standard fields included, in `Order_Hub_Integration`. Use `WITH SYSTEM_MODE`
  / `AccessLevel.SYSTEM_MODE` only with a stated reason.

## Static analysis

- Code Analyzer (`code-analyzer.yml`, Recommended rules) fails CI on High and
  Critical findings; Moderate and Low are reported only.
- A rule that does not fit the project is disabled in `code-analyzer.yml`
  with its reason. An exception for one class is
  `@SuppressWarnings('PMD.<Rule>')` on that class, with a comment saying why.
- Do not add `WITH USER_MODE` / `as user` just to satisfy
  `ApexCRUDViolation`: user mode is the default, and the
  `ApexMinimumApiVersion` rule keeps classes on API 67.0 or later.

## Tests

- Every class has a test class named `<ClassName>Test`.
- Use the `Assert` class (`Assert.areEqual`, `Assert.isTrue`, …), with a
  message when the reason for a failure would not be obvious.
- Test names describe behaviour: `invoicesOrderWhenItBecomesPaid`, not
  `testMethod1`.
- Cover the happy path, negative paths and a 200-record bulk case for any code
  that performs DML. Bulk tests assert on governor limit usage where relevant.
- Code that runs as a restricted user (integration user, guest user) has a
  test that runs it with `System.runAs` as a user holding only its permission
  set; see `ShopifyWebhookProcessorTest`.
- Callouts are tested with `HttpCalloutMock`; Platform Event subscribers are
  tested with `Test.stopTest()` or `Test.getEventBus().deliver()`.
- Shopify payloads come from `ShopifyTestData` and its static resource
  fixtures, not hand-written JSON, unless a test needs a specific edge case.
- Aim for meaningful coverage; anything below 90% on a new class needs a
  reason.
