# GitHub Actions CI setup and pilot

## Status as of 2026-11-18

- [x] Windows and Linux 1ES managed runners allocate and execute jobs.
  Both runner jobs passed in [infrastructure smoke run 44395543761](https://github.com/microsoft/vcpkg/actions/runs/44395543761).
  An administrator resolved the runner configuration issue; the specific fix
  has not been recorded.
- [ ] **Blocked: approved Azure authentication and authenticated storage access.**
  Both Azure login jobs in that run failed. Federated identity credentials (FICs)
  have no approved path forward yet. Tenant administrators must resolve this
  before cache or registry acceptance testing can proceed.
- [ ] Determine whether the required identities, storage accounts, registry, and
  dependent resources must be recreated outside the corporate tenant.
  Resource reuse below is conditional on that decision, not an accepted assumption.
- [ ] Resume the pilot only after authenticated storage and registry operations
  work. Runner success alone does not establish cache, container, or build readiness.

The migration is preserved on `BillyONeal/vcpkg:adopt-github-actions-2026-11-17`.
The corresponding branch in `microsoft/vcpkg` is planned for deletion while
authentication is blocked. Do not rely on that upstream branch for recovery.
Azure Pipelines remains the production system; the full migration is not ready
to merge because it removes the existing pipelines.

This is the provisioning and acceptance checklist for the migration. Resource
names match the proposed workflows, not a verified Azure inventory. Keep
pilot-only changes separate from changes intended for `master`. Future pilot
examples target `microsoft/vcpkg:actions-ci-test`, with PR heads in
`BillyONeal/vcpkg`; those are not instructions to start the pilot while blocked.

## 1. Azure resources and authentication

### Decide whether to reuse or recreate resources

- [ ] Obtain an approved tenant/subscription and authentication design before
  provisioning replacements. Do not bypass tenant policy.
- [ ] Confirm the tenant, subscription, resource group, and network restrictions
  for each existing resource, and record its replacement if required:

  | Existing resource | Required content/use |
  | --- | --- |
  | Storage account `vcpkgassetcachewus` | Blob container `cache`; source/asset cache |
  | Storage account `vcpkgbinarycachewus` | Blob container `cache`; binary cache |
  | ACR `vcpkgandroidwus` | Linux, ARM64 cross-compilation, and Android images |
  | Windows Azure Compute Gallery image | Source for a 1ES Windows image |
  | Linux Docker-host image | Source for a 1ES Linux image |
  | Storage account `vcpkgimageminting` | Existing image-building assets, if rebuilding images |

- [ ] If resources must move, determine cache-content and image migration needs.
  Update all affected workflow URLs, registry/image references, provisioning
  scripts, RBAC assignments, and environment variables consistently. Revalidate
  access from every runner family; do not silently fall back to uncached builds.
- [ ] Preserve the existing resources and Azure DevOps access during the pilot.
  Do not delete working production resources to provision replacements.
- [ ] Check that storage SAS expiration policies permit **four days plus
  30 minutes** between signed start and expiry. The proposed workflow backdates
  the start by 30 minutes and sets expiry four days ahead.
- [ ] Check network access from credential-minting jobs to Azure login, Storage
  user-delegation-key endpoints, and ACR authentication endpoints. RBAC grants do
  not bypass firewalls.
- [ ] Check access from both runner pools and the Macs to caches, the registry,
  GitHub Actions/artifact endpoints, and upstream download sites.

Published cache credentials are intentionally available to signed-in artifact
downloaders. Asset SAS permissions are `rcl`; binary SAS permissions are `rclw`.
Use them only for the public/untrusted CI caches, never private data.

### Two workflow identities

Keep the credential minter and image publisher as separate identities.
Existing Azure DevOps identities can technically accept additional FICs, but
reuse depends on the tenant decision above.

- [ ] Inspect the identities behind Azure DevOps service connections
  `vcpkg-pr-fleet-wus` and `containers-updater`. Connection names need not be
  identity resource names.
- [ ] Audit existing roles before reusing identities. A GitHub login receives
  all of the identity's existing permissions. Keep registry push rights off
  the credential minter.
- [ ] If replacements are required, create identities in the approved tenant.
  Suggested names: `vcpkg-gha-ci-credentials` and
  `vcpkg-gha-container-publishing`.
- [ ] Record each identity's client ID, principal/object ID, tenant ID, and
  subscription ID in the appropriate configuration, not this checklist.
  Workflow variables use the **client ID**; RBAC assignments use the
  **principal/object ID**.
- [ ] Assign these roles, using replacement resource names if applicable:

  | Identity | Role | Scope |
  | --- | --- | --- |
  | Credential minter | Storage Blob Delegator | Asset storage account |
  | Credential minter | Storage Blob Data Contributor | Its `cache` container |
  | Credential minter | Storage Blob Delegator | Binary storage account |
  | Credential minter | Storage Blob Data Contributor | Its `cache` container |
  | Credential minter | AcrPull | Container registry |
  | Container publisher | AcrPush | Container registry |

  Container scope ends in `/blobServices/default/containers/cache`. Delegator
  must be assigned at account scope or above. No account keys or subscription
  Contributor role are needed by these workflows.

  These ACR roles assume **RBAC Registry Permissions** mode. In **RBAC Registry
  + ABAC Repository Permissions** mode, use appropriate Repository Reader/Writer
  roles and repository conditions instead. Do not change production registry
  mode merely for this pilot.

### Federation

- [x] Restore the repository's ID-only custom subject template:
  `use_default=false`, `use_immutable_subject=false`, with claim keys
  `repository_owner_id`, `repository_id`, `context`.
- [ ] Confirm that template remains in effect before configuring FICs.
  Subject customization affects all OIDC consumers in the repository.
- [ ] Configure the approved identities to trust **microsoft/vcpkg**, not the fork:

  | Field | Value |
  | --- | --- |
  | Issuer | `https://token.actions.githubusercontent.com` |
  | Audience | `api://AzureADTokenExchange` |
  | Immutable owner ID | `6154722` |
  | Immutable repository ID | `68312233` |
  | Minter subject | `repository_owner_id:6154722:repository_id:68312233:environment:ci-credentials` |
  | Publisher subject | `repository_owner_id:6154722:repository_id:68312233:environment:container-publishing` |

  These are GitHub numeric IDs, not Azure object/client IDs or GitHub GraphQL IDs.
  Environment deployment restrictions control which branches may use the subjects.
- [ ] Resolve the `AADSTS53003` authentication blocker with tenant administrators.
  Do not assume changing runners or the subject format overrides tenant policy.
- [ ] Rerun both Azure logins and actual storage/registry operations after the
  approved configuration is available. `AADSTS700213` indicates a FIC mismatch;
  compare the emitted subject, issuer, and audience exactly.
- [ ] Allow for RBAC/federation propagation when validating changes.
- [ ] Keep existing Azure DevOps credentials until both systems have been validated.
- [ ] Do not attach either privileged identity to VMs executing fork PR code.
  Build jobs consume published short-lived credentials instead.

### Scratch container repositories

- [ ] Once a registry is available, use three scratch repositories:
  `vcpkg-linux-actions-pilot`, `vcpkg-arm64-linux-actions-pilot`, and
  `vcpkg-android-actions-pilot`. The first successful push creates them.
- [ ] In the pilot [container updater](.github/workflows/update-containers.yml),
  replace production repository names in all build, push, and lifecycle commands.
- [ ] Update the corresponding images in
  [the build workflow](.github/workflows/test-modified-ports.yml).
  Do not overwrite or annotate production images during the pilot.

## 2. Managed runners

- [x] Provision Windows and Linux 1ES pools and resolve job allocation.
- [x] Verify the smoke workflow's `self-hosted`, `1ES.Pool=...`, and unique
  `JobId=...` labels allocate runners.
- [x] Windows smoke check: PowerShell, Git, and writable `D:\`.
- [x] Linux smoke check: Git, passwordless sudo, Docker, Buildx, and writable `/mnt`.

These results are from run `44395543761`, not full port builds.

| Pool | Intended host | Full-run build concurrency |
| --- | --- | --- |
| `vcpkg-pr-windows` | x64 Windows with vcpkg VS/toolchain image | 7 |
| `vcpkg-pr-linux` | x64 Linux Docker host; ARM64 builds cross-compile | 5, plus overlapping image updates |

- [ ] Retain the working pool/runner-group configuration. Verify fork PR access
  separately, preserving any required run approvals and read-only fork tokens.
- [ ] Confirm the production workflow's
  `1ES.ImageOverride=vcpkg-windows-2026-10-27` label is supported and names the
  correct image. The successful smoke test omitted this label and used the pool
  default. If unsupported, pin the pool default and remove the extra demand.
- [ ] Keep matrix indexes in build-job IDs. Revalidate allocation after any label
  changes; smoke-test success does not validate additional production demands.
- [ ] Size pools and regional VM quota for the matrix and GitHub's 24-hour
  self-hosted queue limit.
- [ ] Configure disposable/reimaged workers between untrusted jobs. Confirm VM
  lifetimes cover the configured 48-hour Windows and 24-hour Linux jobs.
- [ ] Verify all Windows toolchain components from the
  [provisioning scripts](.github/ci/windows), not only the smoke-test tools.
- [ ] Verify Linux `systemctl`, Docker restart/data-root changes, Azure CLI, ORAS,
  and artifact connectivity. The image updater needs Azure CLI and ORAS on the
  host; build dependencies inside containers are not sufficient.
- [ ] If rebuilding images, review the resource and permission assumptions in
  [create-image.ps1](.github/ci/windows/create-image.ps1). Image-provisioning
  identities are separate from the workflow identities above.

## 3. GitHub settings and macOS

- [ ] Permit pinned `actions/*`, `azure/login`, and existing CodeQL actions under
  repository/organization policy.
- [ ] Configure environments `ci-credentials` and `container-publishing`.
  Restrict deployments to `master`; temporarily add `actions-ci-test` for the
  pilot, never arbitrary PR refs.
- [ ] In each environment, set `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and
  `AZURE_SUBSCRIPTION_ID` for its approved identity. These are variables, not
  client secrets. Recheck them if resources move.
- [ ] Avoid human approval on the hourly credential minter. Decide explicitly
  whether publisher approval is compatible with an unattended weekly schedule.
- [ ] Permit four-day credential artifact retention and choose failure-log
  retention/storage budgets.
- [ ] Preserve the required `Check` job. Do not require new build checks until
  pilot acceptance; use the actual observed check names.
- [ ] Register at least one ARM64 Mac against `microsoft/vcpkg`, following the
  [macOS deployment checklist](.github/ci/osx/README.md).
- [ ] Verify `self-hosted`, `macOS`, `ARM64`, and
  `vcpkg-osx-2026-10-19-arm64` labels, or update the workflow to the actual image.
  Verify PowerShell, Xcode, writable `~/Data`, and cache/artifact connectivity.
- [ ] Verify VM reset/relaunch between untrusted jobs. `macosvm --ephemeral`
  discards changes on VM exit; it does not restart a VM between runner jobs.

Fork PRs must not need OIDC, fork secrets, storage account keys, or a privileged
identity attached to their runners. They still require working published cache
credentials. The new workflows intentionally skip execution in fork-local runs.

## 4. Resume the infrastructure smoke test

The minimal manual smoke workflow landed on upstream `master` independently of
the full migration. Its runner checks passed; its Azure checks remain blocked.

- [ ] After authentication is approved, rerun **Test CI Infrastructure** on
  `master`, using the working Windows/Linux pools.
- [ ] `ci-credentials`: verify OIDC login, both user-delegation SAS tokens listing
  their cache containers, and ACR token minting.
- [ ] `container-publishing`: verify OIDC login and ACR token minting. This is
  not proof of AcrPush; a real scratch-image push is still required.
- [ ] If resource names change, update the smoke workflow before rerunning it.

## 5. Prepare a non-default pilot branch

**Do not begin until authenticated storage and registry access are available.**
Do not merge the full migration just to test infrastructure.

- [x] Preserve the production migration baseline, commit `996d5ff68f`, on the
  fork's `adopt-github-actions-2026-11-17` branch.
- [ ] Create a separate `microsoft/vcpkg:actions-ci-test` branch from the migration
  after incorporating the approved resource configuration.

The production YAML selects `master` for PRs, comparisons, and credential lookup.
New manual workflows must exist on the default branch to be dispatchable;
schedules run only on the default branch. Make these **pilot-only** edits:

- [ ] Add `actions-ci-test` to the build workflow's PR branches. Initially leave
  its push filter as `master` to avoid expensive full builds on setup commits.
- [ ] In [get-ci-credentials](.github/actions/get-ci-credentials/action.yml), use
  `actions-ci-test` instead of `master` for workflow-run lookup and its diagnostic.
- [ ] Change the comparison branch in
  [test-modified-ports.ps1](.github/ci/test-modified-ports.ps1) and the default
  target branch in [build-file-lists.ps1](.github/ci/build-file-lists.ps1) to
  `origin/actions-ci-test`.
- [ ] Add a `push` trigger for `actions-ci-test` to
  [mint-ci-credentials.yml](.github/workflows/mint-ci-credentials.yml).
  This replaces scheduled minting during the non-default-branch pilot.
- [ ] Add a pilot-branch push trigger to the container updater, restricted to
  `.github/ci/pilot-container-trigger.txt`. Do not create the marker until
  scratch repository configuration is ready.
- [ ] Keep all 13 triplets enabled, or explicitly narrow the plan fallback.
  Its selector is a substring of `^<triplet>$`, not a regular expression:
  `^x64-linux$` selects that triplet, `windows` selects Windows, `^` selects all.
  Dispatch defaults alone do not narrow PR/push events.
- [ ] Push the pilot branch without changing the repository default branch.

Refresh credentials at least hourly during testing, or run small batches right
after a refresh. SAS tokens last four days, but ACR tokens last approximately
three hours; long queue waits can exhaust them before image pulls. Push a fresh
pilot commit after workflow changes rather than rerunning an old workflow revision.
The existing [CodeQL workflow](.github/workflows/codeql.yml) needs no new Azure
resources; its unchanged push filter is `master`.

## 6. Acceptance tests

Record run URLs, commit SHAs, triplets, cache hit counts, elapsed times, and
artifact-download results. Local lint and runner smoke checks are not substitutes.

### A. Credentials and container publishing

- [ ] Pilot push successfully runs credential login, minting, and publication.
- [ ] Verify the `ci-credentials` artifact belongs to the pilot branch and has
  fields `minted`, `sasExpiry`, `acrTokenExpiry`, `assetSas`, `binarySas`,
  and `acrToken`. Inspect timestamps without copying token values into logs.
  SAS expiry should be about four days away; recorded ACR expiry about 170 minutes.
- [ ] Create/commit the pilot container marker. Verify the publisher logs in on
  Linux, builds all three images, and pushes only scratch repositories within
  the 60-minute timeout.
- [ ] Publish again and verify previous-image lifecycle annotations and new-tag
  pulls. Initial missing-image warnings are not permission to ignore recurring
  authentication or missing-ORAS errors.

### B. Real fork PR and warm-cache reuse

- [ ] Branch from upstream `actions-ci-test` in the fork. Include pilot setup in
  ancestry so infrastructure changes do not become part of the test-port diff.
- [ ] Add a tiny, uniquely named cross-platform compiled port with installed
  header/library, valid metadata/license, and normal version registration.
- [ ] Push the fork branch and have the user open a PR targeting upstream
  `actions-ci-test`. Approve the run if required.
- [ ] Confirm it is an upstream `pull_request` run, not a fork-local push.
  `Check` must pass; the full matrix is seven Windows, one macOS, five Linux/Android.
- [ ] Every platform downloads pilot credentials with the ordinary read-only
  PR `GITHUB_TOKEN`, without OIDC or fork secrets.
- [ ] Verify all three container families pull, including ARM64 cross-compilation
  and an Android triplet.
- [ ] Verify **Pull Request / read write** binary caching, feature testing,
  comparison against the pilot target, asset-cache use, and binary restores.
- [ ] Rerun the same commit and require a nonzero binary restore count with no
  cache authorization failures. An uncached successful build is not sufficient.
- [ ] Download Windows, macOS, and Linux file-list artifacts. Their roots must
  contain `VCPKGDatabase.txt` and `VCPKGHeadersDatabase.txt` with the test port.
  Verify warm-cache file lists too; those are recovered from binary-cache ZIPs.

### C. Build failure and contributor log access

- [ ] Make another fork PR with a distinct version/ABI and a real compiler
  failure, such as `#error VCPKG_ACTIONS_PILOT_FAILURE`. Register versions normally;
  do not add a failure baseline.
- [ ] Verify failure at `*** Test Modified Ports` and execution of publishing/
  summary steps on Windows, macOS, and a container job.
- [ ] Download `failure logs for <triplet>` and find the compiler error marker.
  Verify the summary has the failed port/log tail and a working artifact link.
- [ ] Verify download using a signed-in account without repository write access.
  Signed-out artifact download is not required.
- [ ] Fix the port and confirm success. Update another active PR run to verify
  cancellation of superseded runs and fresh credential lookup in the new run.

### D. Metadata and infrastructure failures

- [ ] Test nonexistent dependency version constraints and malformed/unformatted
  metadata in separate small PRs. `Check` must fail with actionable diagnostics.
- [ ] Exercise actual cache requests and image pulls; artifact presence alone
  does not establish authorization or credential freshness.
- [ ] Do not revoke production roles or poison shared caches for negative tests.
  Use isolated pilot fixtures for stale-token tests and restore normal lookup.

### E. Long-running jobs and late artifacts

This is a release gate. Self-hosted execution can exceed six hours, but
`GITHUB_TOKEN` expires after at most 24 hours; artifact transport must be tested.

- [ ] In a pilot-only commit, select one Windows triplet. After a successful
  small build and before failure-log publication, add a 90,000-second wait,
  create a new staged failure log, and deliberately fail. Do not use a step timeout.
- [ ] Verify the worker survives beyond six hours and that the newly created
  log is uploaded and downloadable after 25 hours. Also verify the later summary
  and file-list upload. Ordinary runner logs do not prove artifact upload works.
- [ ] Verify cache requests late in a real build, within the four-day SAS lifetime.
  Images should already be pulled; no late ACR login is required.
- [ ] Remove the synthetic step and restore the matrix. Stop rollout if late
  publication fails; contributor failure logs are essential.

### F. Non-PR/write-only mode

- [ ] After PR acceptance, temporarily add `actions-ci-test` to the build push
  filter and narrow the fallback to one triplet.
- [ ] Verify **CI / write only** caching and full selected-triplet registry
  behavior rather than PR selection. Budget for expensive builds: binary
  restores are intentionally disabled; asset caching must remain active.
- [ ] Verify artifacts and installed-file lists. If custom vcpkg-tool builds
  are required, test a known SHA on each host family, including Linux bootstrap pulls.

## 7. Cutover and rollback

- [ ] Keep production and pilot-only commits separate. Exclude synthetic ports,
  marker files, narrowed matrices, scratch images, and pilot branch references.
- [ ] Land credential minting separately on `master` first. Dispatch it and verify
  usable credentials before enabling new master builds.
- [ ] Merge remaining migration changes with production resources, refs, and
  pool labels restored. Restrict Azure-login environments to `master` afterward.
- [ ] Observe actual hourly mint runs (`17 * * * *`) and Sunday container updates
  (`0 0 * * 0`, UTC). Non-default-branch runs do not establish schedules work.
  Alert on failed/missing mint runs; delayed schedules can leave ACR tokens stale.
- [ ] Remove pilot marker triggers and marker files together. Retire scratch
  images only when no active run needs them.
- [ ] Change required checks only after acceptance, then disable old Azure
  Pipelines triggers/integration. Preserve old logs and production resources.
- [ ] Roll back by restoring prior pipeline YAML/triggers and branch rules.
  Do not dismantle Azure DevOps resource access before long-run, cache,
  contributor-download, and scheduled-run acceptance.

## Public references

- [Azure DevOps public project retirement](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/public-projects-retirement)
- [GitHub Actions limits](https://docs.github.com/en/actions/reference/limits)
- [Job token lifetime](https://docs.github.com/en/actions/concepts/security/github_token)
- [Manual dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [GitHub OIDC subjects](https://docs.github.com/en/actions/reference/security/oidc)
- [Azure user-delegation SAS](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-user-delegation-sas-create-cli)
- [ACR authentication](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication)
- [ACR RBAC/ABAC roles](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)
