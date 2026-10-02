---
name: review-vcpkg-pr
description: Review a microsoft/vcpkg pull request end-to-end.
---

## Inputs

| Input | Required | Meaning |
|---|---|---|
| `pr` | Yes | Pull request number to review. Substituted for `{{PR_NUMBER}}` throughout this skill and the shared guide. |
| `investigation-root` | No | Directory for workspaces and intermediate artifacts: sources, builds, installs, logs, and examples. If omitted, infer a short same-drive path when clear; otherwise ask. Never use the Copilot session directory or an arbitrary long temp path. |
| `review-depth` | No | One of `no-examples`, `examples`, or `examples-and-patches`. Default to `no-examples`. |

### Example invocations

- `/review-vcpkg-pr 12345`
- `/review-vcpkg-pr 12345 investigation-root D:/vcpkg-prs`

## Review requirements

Before changing directories, resolve `investigation-root` and `reviews/pr-{{PR_NUMBER}}` against the caller's original directory to absolute paths. Use the resolved report directory as `{{REPORT_DIR}}` throughout this skill and the shared guide; never rebase it onto the review workspace.

Use the shared helpers from the caller's repository root (resolve their paths before changing directories):

1. Run [Get-VcpkgReviewEvidence.ps1](../shared/Get-VcpkgReviewEvidence.ps1) with `-InvestigationRoot <absolute-path> -PrNumber {{PR_NUMBER}}`. It returns a compact summary and the absolute `manifestPath`; raw evidence stays on disk.
2. Run [New-VcpkgReviewWorkspaces.ps1](../shared/New-VcpkgReviewWorkspaces.ps1) with `-ManifestPath <manifestPath> -CallerRoot <original-repository-root> -ReviewsRoot <absolute-reviews-root>`. Read the returned `workersPath` and use its ready worker's absolute paths. Do not review a failed entry; surface its reason. Recollect if the PR revision changed.
3. In one parallel read batch, read both entire guides using the worker's `guidePath`/`guideReadRanges` and `maintainerGuidePath`/`maintainerGuideReadRanges`, provenance at `maintainerGuideMetadataPath`, and `evidenceRoot/pr-summary.json`. Pass each range's `start`/`end` as `view_range`. Every instruction in the shared guide is mandatory. Batch subsequent independent evidence reads too. Do not download another maintainer guide; cite its pinned source URL.

Review in the prepared workspace, never switch branches or run mutable review steps in the caller's working tree. See [shared helper documentation](../shared/review-helpers.md) only if needed.

If `VCPKG_DOWNLOADS` is already nonempty, preserve it for all review commands and subagents. Use that shared directory only through vcpkg; never clean or delete it. Otherwise, do not set it.

## Required outputs

Write only final deliverables in `{{REPORT_DIR}}`, not under `investigation-root`. The shared guide defines their contents:

1. `report.md`, including the guide's self-contained `## Fix handoff` for use without this session's chat history.
2. `patches/*.patch` -- only for `examples-and-patches`; omit if no patches were produced and explain any unpatched issues in the report.

Do not stop until `report.md` exists in `{{REPORT_DIR}}` and is complete.
