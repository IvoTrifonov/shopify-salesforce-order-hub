# 4. Run webhook processing as a dedicated integration user

**Status:** Accepted

## Context

The `Shopify_Webhook__e` trigger ran as the Automated Process user, so every
Account, Contact, Order and Invoice created from Shopify was created and
owned by that system user. It has broad, implicit access, cannot be given
permission sets, and makes integration records indistinguishable from other
platform automation in audit fields and reports.

`PlatformEventSubscriberConfig` can set the running user of a Platform Event
trigger, but it references the user by username. Usernames are
org-specific and this repository is public, so the username must not be
committed.

## Decision

- An **Order Hub Integration** user with the free `Salesforce Integration`
  license, the `Minimum Access - API Only Integrations` profile and the
  `Salesforce API Integration` permission set license. It cannot log in to
  the UI. It is created once in Setup; it is org data, not metadata.
- The `Order_Hub_Integration` permission set grants it only what the
  processor needs: create, read and edit on Account, Contact, Order, Product2
  and `Invoice__c`; read and edit on `Sync_Log__c`; read on Pricebook2 and
  `Shopify_Webhook__e`; and the custom fields involved. No delete, no View
  All or Modify All.
- `ShopifyWebhookEventTriggerConfig` sets `<user>` to the placeholder
  `${SF_INTEGRATION_USERNAME}`. A `replacements` entry in `sfdx-project.json`
  swaps in the `SF_INTEGRATION_USERNAME` environment variable at deploy time:
  a repository secret in GitHub Actions, and a user environment variable for
  local deploys.

## Consequences

- Records from Shopify are created and owned by Order Hub Integration, so
  they can be told apart from manual and automated changes.
- A deploy without `SF_INTEGRATION_USERNAME` fails before anything is sent
  to the org. It cannot silently revert the trigger to Automated Process.
- Retrieving the subscriber config from the org writes the real username
  into the source file. Restore the placeholder before committing.
- The processor's Apex runs in system mode, so the permission set does not
  restrict what it can do today. It documents the intended access, gives the
  user access to the records it owns, and is enforced as soon as code moves
  to user mode.
- A new org needs the user created and the permission set assigned before
  the first deploy, or the deploy fails because the username does not exist.
