[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shared = Split-Path $PSScriptRoot
$collector = Join-Path $shared 'Get-VcpkgReviewEvidence.ps1'
$preparer = Join-Path $shared 'New-VcpkgReviewWorkspaces.ps1'
$rangesScript = Join-Path $shared 'Get-VcpkgReviewReadRanges.ps1'
$script:GitExecutable = (Get-Command git -CommandType Application).Source
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vcpkg-review-tests-" + [guid]::NewGuid().ToString('N'))
$caller = Join-Path $testRoot 'caller'
$originalDownloads = $env:VCPKG_DOWNLOADS

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-ReadRanges {
    param([string]$Path, [object[]]$Ranges)
    $lines = @(Get-Content -LiteralPath $Path)
    $next = 1
    foreach ($range in $Ranges) {
        Assert ($range.start -eq $next -and $range.end -ge $range.start) 'contiguous nonempty read ranges'
        $text = ($lines[($range.start - 1)..($range.end - 1)] -join "`r`n") + "`r`n"
        Assert ([System.Text.Encoding]::UTF8.GetByteCount($text) -le 18000) 'read range is at most 18000 UTF-8 bytes'
        $next = $range.end + 1
    }
    Assert ($next -eq $lines.Count + 1) 'read ranges cover every line exactly once'
}

function Invoke-RealGit {
    param([string[]]$Arguments)
    $output = & $script:GitExecutable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Test Git setup failed: $($Arguments -join ' ')" }
    return ($output -join "`n")
}

function gh {
    $context = $global:VcpkgReviewHelperTestContext
    $global:LASTEXITCODE = 0
    $endpoint = [string]$args[1]
    if ($endpoint -eq 'repos/MicrosoftDocs/vcpkg-docs/commits/main') {
        if ($context.GuideFailure) {
            $global:LASTEXITCODE = 1
            return
        }
        return '{"sha":"abcdef123456"}'
    }
    if ($endpoint -like 'repos/MicrosoftDocs/vcpkg-docs/contents/*') {
        $context.GuideFetches++
        return '# Mock maintainer guide'
    }
    if ($endpoint -like 'search/issues*') {
        $items = @(if (-not $context.EmptySearch) { @{number=101}; @{number=102}; @{number=103} })
        $result = @{ total_count = $items.Count; incomplete_results = $context.IncompleteSearch; items = $items }
        if ($context.OversizedSearch) { $result.total_count = 1001 }
        if ($args -contains '--slurp') {
            return (ConvertTo-Json -InputObject @($result) -Depth 20)
        }
        return (ConvertTo-Json -InputObject $result -Depth 20)
    }
    if ($endpoint -match '^repos/microsoft/vcpkg/pulls/(\d+)$') {
        $number = [int]$Matches[1]
        if ($number -eq 103) {
            $global:LASTEXITCODE = 1
            return
        }
        if ($args -contains 'Accept: application/vnd.github.diff') { return 'mock diff' }
        if (-not $context.PrReads.ContainsKey($number)) { $context.PrReads[$number] = 0 }
        $context.PrReads[$number]++
        $head = if ($context.MovingHead -and $context.PrReads[$number] -gt 1) { 'changed' } else { $context.HeadSha }
        $user = if ($number -eq 102) { $null } else { @{login='contributor'; metadata=('x' * 1000)} }
        $headRepo = if ($number -eq 102) { $null } else { @{full_name='contributor/vcpkg'; metadata=('x' * 1000)} }
        return (ConvertTo-Json -InputObject @{
            number = $number; title = "PR $number"; html_url = "https://github.com/microsoft/vcpkg/pull/$number"
            body = "Full description`nwith details"; user = $user; state = 'open'; draft = $false
            created_at = '2026-09-01T00:00:00Z'; updated_at = '2026-10-01T00:00:00Z'
            head = @{sha=$head; ref='feature'; repo=$headRepo}
            base = @{sha=$context.BaseSha; ref='master'; repo=@{full_name='microsoft/vcpkg'; metadata=('x' * 1000)}}
            changed_files = $context.ExpectedFiles; redundant_api_urls = ('x' * 4000)
        } -Depth 20)
    }
    if ($endpoint -match '/files\?') {
        # Two pages exercise pagination flattening and renamed-port discovery.
        $pages = @(
            ,@(@{filename='ports/alpha/vcpkg.json'})
            ,@(@{filename='ports/beta/portfile.cmake'; previous_filename='ports/old/portfile.cmake'})
        )
        return (ConvertTo-Json -InputObject $pages -Depth 20)
    }
    if ($endpoint -match '/check-runs\?') {
        return (ConvertTo-Json -InputObject @(@{check_runs=@(@{
            id=4; name='CI'; head_sha=$context.HeadSha; status='completed'; conclusion='failure'
            html_url='https://github.com/check/4'; details_url='https://dev.azure.com/vcpkg/public/_build/results?buildId=42'
            output=@{title='Failed'; summary='regression'; text='diagnostic'; annotations_count=1; annotations_url='https://github.com/check/4/annotations'}
            redundant_api_urls=('x' * 2000)
        })}) -Depth 20)
    }
    if ($endpoint -match '/102/comments\?') { return '[[]]' }
    if ($endpoint -match '/(comments|reviews)\?') {
        $item = @{
            id=1; user=@{login='reviewer'; metadata=('x' * 1000)}
            html_url='https://github.com/comment/1'; body="Full feedback`nwith details"
            created_at='2026-10-01T00:00:00Z'; updated_at='2026-10-02T00:00:00Z'
            redundant_api_urls=('x' * 2000)
        }
        if ($endpoint -match '/reviews\?') {
            $item.state = 'CHANGES_REQUESTED'
            $item.submitted_at = '2026-10-01T00:00:00Z'
            $item.commit_id = $context.HeadSha
        } elseif ($endpoint -match '/pulls/') {
            $item.pull_request_review_id = 2
            $item.in_reply_to_id = 3
            $item.path = 'ports/alpha/vcpkg.json'
            $item.diff_hunk = '@@ -1 +1 @@'
            $item.line = 1
            $item.side = 'RIGHT'
            $item.commit_id = $context.HeadSha
            $item.original_commit_id = $context.BaseSha
        }
        return (ConvertTo-Json -InputObject (, @($item)) -Depth 20)
    }
    throw "Unexpected mock GitHub request: $endpoint"
}

function git {
    $context = $global:VcpkgReviewHelperTestContext
    $arguments = @($args)
    if ($arguments.Count -gt 2 -and $arguments[2] -eq 'fetch') {
        if ($context.FetchFailure) {
            $global:LASTEXITCODE = 1
            return
        }
        $revision = [string]$arguments[-1]
        if ($revision -like 'refs/pull/*/head') {
            $revision = if ($context.FetchHeadOverride) { $context.FetchHeadOverride } else { $context.HeadSha }
        }
        $arguments = @('-C', $arguments[1], 'fetch', '--no-tags', $arguments[1], $revision)
    }
    $output = & $context.GitExecutable @arguments
    $global:LASTEXITCODE = $LASTEXITCODE
    return $output
}

try {
    New-Item -ItemType Directory -Path $caller -Force | Out-Null
    foreach ($path in @($collector, $preparer, $rangesScript)) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert ($errors.Count -eq 0) "PowerShell syntax: $path"
    }
    $rangeFixture = Join-Path $testRoot 'guide-ranges.txt'
    Set-Content -LiteralPath $rangeFixture -Value @((1..772) | ForEach-Object { 'x' * 55 }) -Encoding utf8
    $ranges = @(& $rangesScript -Path $rangeFixture)
    Assert-ReadRanges -Path $rangeFixture -Ranges $ranges
    Assert ($ranges.Count -eq 3) '43 KB guide needs three reads, not twenty'
    Set-Content -LiteralPath $rangeFixture -Value @(('x' * 17998), 'next') -Encoding utf8
    $ranges = @(& $rangesScript -Path $rangeFixture)
    Assert-ReadRanges -Path $rangeFixture -Ranges $ranges
    Assert ($ranges.Count -eq 2 -and $ranges[0].end -eq 1) 'exact byte-budget boundary'
    Set-Content -LiteralPath $rangeFixture -Value @((1..4) | ForEach-Object { ([string][char]0x00e9) * 4000 }) -Encoding utf8
    $ranges = @(& $rangesScript -Path $rangeFixture)
    Assert-ReadRanges -Path $rangeFixture -Ranges $ranges
    Assert ($ranges.Count -eq 2) 'byte budget handles multibyte text'
    foreach ($invalidText in @('', ('x' * 18000))) {
        [System.IO.File]::WriteAllText($rangeFixture, $invalidText)
        $threw = $false
        try { & $rangesScript -Path $rangeFixture | Out-Null } catch { $threw = $true }
        Assert $threw 'empty guides and over-budget individual lines fail explicitly'
    }
    Invoke-RealGit -Arguments @('-C', $caller, 'init', '--quiet') | Out-Null
    Invoke-RealGit -Arguments @('-C', $caller, 'config', 'user.name', 'Review Test') | Out-Null
    Invoke-RealGit -Arguments @('-C', $caller, 'config', 'user.email', 'review-test@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $caller 'fixture.txt') -Value 'base'
    Invoke-RealGit -Arguments @('-C', $caller, 'add', 'fixture.txt') | Out-Null
    Invoke-RealGit -Arguments @('-C', $caller, 'commit', '--quiet', '-m', 'base') | Out-Null
    $script:BaseSha = Invoke-RealGit -Arguments @('-C', $caller, 'rev-parse', 'HEAD')
    Set-Content -LiteralPath (Join-Path $caller 'fixture.txt') -Value 'head'
    Invoke-RealGit -Arguments @('-C', $caller, 'commit', '--quiet', '-am', 'head') | Out-Null
    $script:HeadSha = Invoke-RealGit -Arguments @('-C', $caller, 'rev-parse', 'HEAD')
    $global:VcpkgReviewHelperTestContext = @{
        GitExecutable = $script:GitExecutable
        HeadSha = $script:HeadSha
        BaseSha = $script:BaseSha
        GuideFetches = 0
        IncompleteSearch = $false
        EmptySearch = $false
        MovingHead = $false
        PrReads = @{}
        FetchHeadOverride = $null
        FetchFailure = $false
        GuideFailure = $false
        OversizedSearch = $false
        ExpectedFiles = 2
    }
    $context = $global:VcpkgReviewHelperTestContext
    $guideDirectory = Join-Path $caller '.github\skills\shared'
    New-Item -ItemType Directory -Path $guideDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $shared 'review-vcpkg-pr-guide.md') -Destination $guideDirectory
    $exeName = if ($env:OS -eq 'Windows_NT') { 'vcpkg.exe' } else { 'vcpkg' }
    Set-Content -LiteralPath (Join-Path $caller $exeName) -Value 'mock executable'
    $before = Invoke-RealGit -Arguments @('-C', $caller, 'status', '--porcelain')
    $env:VCPKG_DOWNLOADS = Join-Path $testRoot 'shared-downloads'

    $evidence = & $collector -InvestigationRoot (Join-Path $testRoot 'runs') -WarningVariable collectionWarnings
    Assert ($evidence.collected -eq 2 -and $evidence.failed -eq 1) 'batch includes explicit acquisition failure'
    Assert ($collectionWarnings.Count -eq 1) 'acquisition failure is surfaced'
    Assert ($context.GuideFetches -eq 1) 'one guide download for the whole batch'
    $manifest = Get-Content -LiteralPath $evidence.manifestPath -Raw | ConvertFrom-Json
    Assert ($manifest.competition.Count -eq 3) 'competition includes new and renamed-away ports'
    Assert (($manifest.prs[0].ports -join ',') -eq 'alpha,beta,old') 'ports from both paginated file-list pages'
    $comments = Get-Content -LiteralPath (Join-Path $manifest.prs[1].evidenceRoot 'comments.json') -Raw
    Assert ($comments.Trim() -eq '[]') 'empty evidence is a JSON array'
    Assert ((Get-FileHash -LiteralPath $manifest.maintainerGuide.path).Hash -eq $manifest.maintainerGuide.sha256) 'guide hash'
    Assert ($manifest.maintainerGuide.sourceUrl -match '/abcdef123456/') 'pinned documentation URL'
    $evidenceRoot = $manifest.prs[0].evidenceRoot
    $summary = Get-Content -LiteralPath (Join-Path $evidenceRoot 'pr-summary.json') -Raw | ConvertFrom-Json
    Assert ($summary.body -eq "Full description`nwith details" -and $summary.author -eq 'contributor') 'complete PR description and author'
    Assert ($summary.head.repository -eq 'contributor/vcpkg' -and $summary.head.ref -eq 'feature') 'contributor handoff metadata'
    Assert ($summary.base.repository -eq 'microsoft/vcpkg' -and $summary.base.sha -eq $script:BaseSha) 'comparison metadata'
    $deleted = Get-Content -LiteralPath (Join-Path $manifest.prs[1].evidenceRoot 'pr-summary.json') -Raw | ConvertFrom-Json
    Assert ($null -eq $deleted.author -and $null -eq $deleted.head.repository) 'deleted author and fork remain explicit nulls'
    foreach ($name in @('comments.json', 'reviews.json', 'review-comments.json', 'checks.json')) {
        $trimmed = Get-Content -LiteralPath (Join-Path $evidenceRoot $name) -Raw
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $evidenceRoot 'raw') $name) -Raw
        Assert ($trimmed.Trim().StartsWith('[')) 'one-item evidence remains an array'
        Assert ($trimmed.Length -lt $raw.Length / 2) "trimmed $name removes redundant metadata"
        Assert ($null -eq ($trimmed | ConvertFrom-Json)[0].PSObject.Properties['redundant_api_urls']) "no API noise in $name"
    }
    $rawPr = Get-Content -LiteralPath (Join-Path (Join-Path $evidenceRoot 'raw') 'pr.json') -Raw
    $summaryText = Get-Content -LiteralPath (Join-Path $evidenceRoot 'pr-summary.json') -Raw
    Assert ($summaryText.Length -lt $rawPr.Length / 2) 'PR summary removes redundant metadata'
    $comment = @(Get-Content -LiteralPath (Join-Path $evidenceRoot 'comments.json') -Raw | ConvertFrom-Json)[0]
    Assert ($comment.body -eq "Full feedback`nwith details" -and $comment.author -eq 'reviewer') 'full conversation content'
    $review = @(Get-Content -LiteralPath (Join-Path $evidenceRoot 'reviews.json') -Raw | ConvertFrom-Json)[0]
    Assert ($review.state -eq 'CHANGES_REQUESTED' -and $review.commit_id -eq $script:HeadSha) 'review state and revision'
    $inline = @(Get-Content -LiteralPath (Join-Path $evidenceRoot 'review-comments.json') -Raw | ConvertFrom-Json)[0]
    Assert ($inline.in_reply_to_id -eq 3 -and $inline.pull_request_review_id -eq 2) 'inline reply relationships'
    Assert ($inline.path -eq 'ports/alpha/vcpkg.json' -and $inline.diff_hunk -eq '@@ -1 +1 @@' -and $inline.line -eq 1) 'inline code location and context'
    $check = @(Get-Content -LiteralPath (Join-Path $evidenceRoot 'checks.json') -Raw | ConvertFrom-Json)[0]
    Assert ($check.conclusion -eq 'failure' -and $check.details_url -match 'buildId=42') 'check result and CI permalink'
    Assert ($check.output.text -eq 'diagnostic' -and $check.output.annotations_count -eq 1) 'check diagnostics'

    $prepared = & $preparer -ManifestPath $evidence.manifestPath -CallerRoot $caller -ReviewsRoot (Join-Path $testRoot 'reviews')
    Assert ($prepared.ready -eq 2 -and $prepared.failed -eq 1) 'two isolated workers plus failed candidate'
    $workers = Get-Content -LiteralPath $prepared.workersPath -Raw | ConvertFrom-Json
    Assert (-not (Get-Command $preparer).Parameters.ContainsKey('ReviewDepth')) 'workspace setup has no review-depth parameter'
    foreach ($worker in $workers.workers | Where-Object status -eq 'ready') {
        Assert ($null -eq $worker.PSObject.Properties['reviewDepth']) 'workspace manifest does not duplicate review depth'
        Assert ((Invoke-RealGit -Arguments @('-C', $worker.workspace, 'rev-parse', 'HEAD')) -eq $script:HeadSha) 'workspace SHA'
        $branch = Invoke-RealGit -Arguments @('-C', $worker.workspace, 'rev-parse', '--abbrev-ref', 'HEAD')
        Assert ($branch -eq 'HEAD') 'detached worktree'
        Assert (Test-Path -LiteralPath (Join-Path $worker.workspace $exeName)) 'copied executable'
        Assert ($worker.downloads -eq $env:VCPKG_DOWNLOADS) 'preserved downloads'
        Assert-ReadRanges -Path $worker.guidePath -Ranges $worker.guideReadRanges
        Assert-ReadRanges -Path $worker.maintainerGuidePath -Ranges $worker.maintainerGuideReadRanges
        Assert ($worker.reportDir.StartsWith($workers.reviewsRoot)) 'fixed report root'
    }
    Assert ((Invoke-RealGit -Arguments @('-C', $caller, 'status', '--porcelain')) -eq $before) 'caller worktree unchanged'

    $rerun = & $preparer -ManifestPath $evidence.manifestPath -CallerRoot $caller -ReviewsRoot (Join-Path $testRoot 'reviews')
    Assert ($rerun.ready -eq 0 -and $rerun.failed -eq 3) 'existing workspaces are not overwritten'

    $context.MovingHead = $true
    $context.PrReads = @{}
    $moving = & $collector -InvestigationRoot (Join-Path $testRoot 'runs') -PrNumber 101
    Assert ($moving.failed -eq 1) 'moving PR revision fails collection'
    $context.MovingHead = $false
    $context.PrReads = @{}
    $single = & $collector -InvestigationRoot (Join-Path $testRoot 'runs') -PrNumber 101
    Assert ($single.collected -eq 1) 'single PR collection'
    $context.FetchHeadOverride = $script:BaseSha
    $stale = & $preparer -ManifestPath $single.manifestPath -CallerRoot $caller -ReviewsRoot (Join-Path $testRoot 'reviews')
    Assert ($stale.failed -eq 1 -and $stale.ready -eq 0) 'head changes before setup fail explicitly'
    $context.FetchHeadOverride = $null
    $context.FetchFailure = $true
    $failedFetch = & $preparer -ManifestPath $single.manifestPath -CallerRoot $caller -ReviewsRoot (Join-Path $testRoot 'reviews')
    Assert ($failedFetch.failed -eq 1) 'native Git failures are detected'
    $context.FetchFailure = $false

    $context.ExpectedFiles = 3001
    $incompleteFiles = & $collector -InvestigationRoot (Join-Path $testRoot 'runs') -PrNumber 101
    Assert ($incompleteFiles.failed -eq 1) 'incomplete changed-file inventory is not review-ready'
    $context.ExpectedFiles = 2
    $context.OversizedSearch = $true
    $threw = $false
    try { & $collector -InvestigationRoot (Join-Path $testRoot 'runs') | Out-Null } catch { $threw = $true }
    Assert $threw 'search over the 1000-result limit terminates explicitly'
    $context.OversizedSearch = $false
    $context.IncompleteSearch = $true
    $threw = $false
    try { & $collector -InvestigationRoot (Join-Path $testRoot 'runs') | Out-Null } catch { $threw = $true }
    Assert $threw 'incomplete search terminates explicitly'
    $context.IncompleteSearch = $false
    $context.EmptySearch = $true
    $empty = & $collector -InvestigationRoot (Join-Path $testRoot 'runs')
    Assert ($empty.collected -eq 0 -and $empty.failed -eq 0) 'empty batch'
    $emptyWorkers = & $preparer -ManifestPath $empty.manifestPath -CallerRoot $caller -ReviewsRoot (Join-Path $testRoot 'reviews')
    Assert ($emptyWorkers.ready -eq 0 -and $emptyWorkers.failed -eq 0) 'empty workspace manifest'
    $context.GuideFailure = $true
    $threw = $false
    try { & $collector -InvestigationRoot (Join-Path $testRoot 'runs') -PrNumber 101 | Out-Null } catch { $threw = $true }
    Assert $threw 'shared documentation acquisition failure terminates explicitly'
    Write-Output 'PASS: shared review helper smoke tests'
} finally {
    Remove-Variable -Name VcpkgReviewHelperTestContext -Scope Global -ErrorAction SilentlyContinue
    $env:VCPKG_DOWNLOADS = $originalDownloads
    # Remove only worktrees created inside this test's unique temporary root.
    if (Test-Path -LiteralPath (Join-Path $caller '.git')) {
        $worktreeLines = & $script:GitExecutable -C $caller worktree list --porcelain
        foreach ($line in $worktreeLines) {
            if ($line -like 'worktree *') {
                $path = $line.Substring(9)
                if ($path -ne $caller.Replace('\', '/') -and $path.StartsWith($testRoot.Replace('\', '/') + '/')) {
                    & $script:GitExecutable -C $caller worktree remove --force $path
                    if ($LASTEXITCODE -ne 0) { throw "Could not clean up test worktree: $path" }
                }
            }
        }
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
