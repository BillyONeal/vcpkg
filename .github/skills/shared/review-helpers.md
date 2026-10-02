# Shared PR review helpers

These PowerShell scripts move deterministic acquisition and setup out of the reviewing model. They require PowerShell 7, authenticated `gh`, Git, and an already bootstrapped caller repository. They do not install tools, modify the caller's checked-out files, launch reviewers, or decide verdicts.

## Usage

Resolve all paths against the original caller directory first. For example, on Windows:

```powershell
$evidence = & 'D:\vcpkg3\.github\skills\shared\Get-VcpkgReviewEvidence.ps1' `
    -InvestigationRoot 'D:\vcpkg-prs' -PrNumber 12345
$workspaces = & 'D:\vcpkg3\.github\skills\shared\New-VcpkgReviewWorkspaces.ps1' `
    -ManifestPath $evidence.manifestPath -CallerRoot 'D:\vcpkg3' `
    -ReviewsRoot 'D:\vcpkg3\reviews'
```

Omit `-PrNumber` for the batch search. An explicit list is also accepted. `-UpdatedSince` overrides the default UTC date minus 30 days. Search results are paginated; incomplete searches and results exceeding GitHub's 1000-result limit fail explicitly.

## Evidence and worker manifests

Each collection creates a unique run directory under `InvestigationRoot`:

- `shared/maintainer-guide.md` and `maintainer-guide.json`: one documentation snapshot pinned to a repository commit, with source URL, retrieval timestamp, and SHA-256 of the stored file.
- `pr-<number>/evidence/pr-summary.json`: trimmed metadata including the full description, author, state, dates, contributor repository/branch, target repository/branch, and head/base revisions.
- `files.json`, `comments.json`, `reviews.json`, `review-comments.json`, and `checks.json`: trimmed paginated evidence. These retain full comment/review bodies, authors, dates, citation URLs, review states/revisions, inline reply IDs and diff locations, check results/CI URLs, and diagnostic output. Changed-file patches are omitted because `pr.diff` supplies the changeset. Empty collections remain JSON arrays. Inline comments do not include GraphQL thread-resolution state; fetch that separately if relevant.
- `raw/`: full REST responses, including `pr.json` and the untrimmed collections, for diagnosis or fields absent from the summaries. Reviewers should not read these by default. `pr.diff` is unchanged.
- `evidence-manifest.json`: compact candidate inventory, affected ports, per-PR collection failures, and port-specific competition groups. Renames account for both old and new port paths.
- `workers.json`: ready/failed entries, absolute workspace/artifact/report paths, both guide paths, evidence location, revisions, and inherited download setting. The invoking skill retains the selected review depth and passes it directly to reviewers.

Workspace preparation copies the local review guide into the run's shared directory, fetches each collected head and base, verifies the head still matches, adds a detached worktree, and copies the caller's vcpkg executable. It does not override or clean `VCPKG_DOWNLOADS`. All workspaces are prepared before workers launch. Do not run concurrent preparers against the same caller repository: fetches use its shared `FETCH_HEAD`.

Read `workers.json` first, then batch reads of both entire guides, provenance, and `pr-summary.json`. The worker manifest supplies `guideReadRanges` and `maintainerGuideReadRanges`, each an array of inclusive 1-based `start`/`end` pairs to pass as `view_range`. [Get-VcpkgReviewReadRanges.ps1](./Get-VcpkgReviewReadRanges.ps1) computes ranges of at most 18,000 UTF-8 bytes, rather than fixed line counts, leaving headroom under the view tool's 20 KB limit. Empty guides or individual lines exceeding that budget fail explicitly. Read trimmed conversation and other evidence in further independent batches. Scripts print only compact summaries, not raw evidence. Reading the complete guides still costs context tokens per worker; this change reduces retrieval turns without dropping review criteria.

## Failure handling and retention

Shared acquisition failures terminate the collector. Individual PR acquisition/setup failures emit warnings and remain explicit failed manifest entries. Use those entries in the final coverage/index, or retry with a new collection. A moving PR head/base or incomplete changed-file list is not review-ready.

Re-running workspace preparation against existing workspaces fails rather than overwriting them. Retain partial evidence and workspaces for diagnosis; the scripts never automatically delete them. Final reports and validated patches belong only under the supplied reviews root, not in the run directory. Generated evidence diffs are not patch deliverables.

## Validation

Run the offline smoke tests from the repository root:

```powershell
pwsh -NoProfile -File .github\skills\shared\tests\Test-VcpkgReviewHelpers.ps1
```

The tests mock GitHub acquisition and network Git fetches, exercise real temporary detached worktrees, and clean up only their own temporary directory.
