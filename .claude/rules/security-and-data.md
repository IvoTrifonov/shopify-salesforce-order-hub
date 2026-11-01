# Security and data

The repository is public.

- No secrets in source control: no webhook secrets, tokens, passwords or auth
  URLs in code, metadata, fixtures, docs or commit messages. Secrets live in
  `Shopify_Settings__c` (entered in Setup) or Named / External Credentials.
- Ask the user to enter secrets in Setup themselves rather than pasting them
  into the chat or passing them on the command line.
- Real Shopify payloads contain personal data. Anonymize them (names, emails,
  phones, addresses, IPs, tokens) before saving them in the repo, and check the
  result for leftovers.
- Org usernames, store URLs and other environment details stay in the
  untracked `local-notes.md`, not in committed files.
- The public webhook endpoint never returns Apex error details to the caller
  and never stores the payload of a request whose signature is invalid.
- The Site guest user keeps the minimum permissions it needs; any new
  permission for it needs a stated reason.
