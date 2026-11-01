# 3. Validate every PR and deploy main with GitHub Actions

**Status:** Accepted

## Context

The project has one Salesforce org, the `orderhub` Developer Edition org,
which is also where the Shopify webhook is processed. There is no Dev Hub
with spare scratch org capacity and no separate staging org.

Changes should be checked before they reach `main`, and the org should not
drift from `main` after a merge. The repository is public, so CI output
must not expose secrets or org details.

## Decision

GitHub Actions runs two workflows:

- **CI** (`ci.yml`, on every pull request to `main`): a `static` job checks
  Prettier formatting, ESLint and LWC Jest tests without an org. A
  `validate` job runs `sf project deploy validate` against `orderhub` with
  `RunLocalTests`. That is a full check-only deployment: it compiles
  everything and runs all local Apex tests, then rolls back.
- **Deploy** (`deploy.yml`, on push to `main` that touches `force-app`):
  `sf project deploy start` with `RunLocalTests`, recorded under the
  `orderhub` GitHub environment.

The workflows log in with an SFDX auth URL stored in the `SFDX_AUTH_URL`
repository secret, read from stdin by a shared composite action
(`.github/actions/sf-setup`). Both org jobs share the `orderhub-org`
concurrency group, because the org runs one deployment at a time.

Coverage is written to the job summary for this project's own classes and
triggers. The JUnit report is not uploaded as an artifact, because it
contains the org's hostname and ID.

## Consequences

- PR validation and the main deploy use the same org as development, so a
  merge overwrites anything deployed by hand that is not on `main`.
- The auth URL holds a refresh token for the integration user. It can be
  revoked in Setup (Connected Apps OAuth Usage) and replaced. A JWT bearer
  flow with an External Client App would avoid a long-lived refresh token
  and is the planned upgrade if a second org is added.
- Pull requests from forks get no secrets, so their `validate` job is
  skipped. They still run the `static` job.
- Salesforce enforces 75% org-wide coverage on deploys with `RunLocalTests`.
  The 90% per-class target is reported in the job summary but not enforced.
- All files are formatted by Prettier and use LF line endings
  (`.gitattributes`); the pre-commit hook formats staged files.
