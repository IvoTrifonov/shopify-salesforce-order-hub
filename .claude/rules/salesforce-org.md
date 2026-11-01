# Salesforce org and deployment

- Every `sf` command that reads or changes an org passes `--target-org orderhub`
  explicitly. Never rely on the default org: other orgs, including production
  orgs, are authorized on this machine.
- Deploy with `--source-dir force-app`. The project has no `package.xml`
  manifest; do not reintroduce one for deployments.
- Validate risky changes with `--dry-run` before deploying.
- Deploy Apex with `--test-level RunLocalTests` (or `RunSpecifiedTests` for a
  quick iteration), as if the org enforced production coverage rules.
- After deploying something that affects the live flow, verify it in the org
  (query `Sync_Log__c`, `Order`, `Invoice__c`) and report what was checked.
- Deleting metadata or data in the org, changing org settings or activating
  records requires telling the user first what will change and why.
- Metadata that cannot be renamed in place (e.g. picklist value API names) may
  need a destructive change; only do that when the affected data is confirmed
  empty or disposable.
