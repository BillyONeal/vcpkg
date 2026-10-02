[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InvestigationRoot,

    [ValidateRange(1, 2147483647)]
    [int[]]$PrNumber,

    [datetime]$UpdatedSince = [datetime]::UtcNow.Date.AddDays(-30)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitHub {
    param([string[]]$Arguments)

    $output = & gh api @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed ($LASTEXITCODE): $($Arguments -join ' ')"
    }
    return ($output -join "`n")
}

function Get-GitHubJson {
    param([string]$Endpoint)
    return (Invoke-GitHub -Arguments @($Endpoint) | ConvertFrom-Json)
}

function Get-GitHubPages {
    param([string]$Endpoint, [string]$ItemsProperty)

    $pages = Invoke-GitHub -Arguments @($Endpoint, '--paginate', '--slurp') | ConvertFrom-Json
    foreach ($page in $pages) {
        if ($ItemsProperty) {
            $page.$ItemsProperty
        } else {
            $page
        }
    }
}

function Write-Json {
    param([string]$Path, [object]$Value)
    ConvertTo-Json -InputObject $Value -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

$author = @{ Name = 'author'; Expression = { if ($_.user) { $_.user.login } else { $null } } }
$url = @{ Name = 'url'; Expression = { $_.html_url } }
$repository = @{ Name = 'repository'; Expression = { if ($_.repo) { $_.repo.full_name } else { $null } } }
$projections = @{
    'files.json' = @('filename', 'previous_filename', 'status', 'additions', 'deletions', 'changes')
    'comments.json' = @('id', $author, $url, 'body', 'created_at', 'updated_at')
    'reviews.json' = @('id', $author, $url, 'body', 'state', 'submitted_at', 'commit_id')
    'review-comments.json' = @(
        'id', $author, $url, 'body', 'pull_request_review_id', 'in_reply_to_id',
        'path', 'diff_hunk', 'line', 'original_line', 'start_line', 'original_start_line',
        'side', 'start_side', 'position', 'original_position', 'subject_type',
        'commit_id', 'original_commit_id', 'created_at', 'updated_at'
    )
    'checks.json' = @(
        'id', 'name', $url, 'details_url', 'head_sha', 'status', 'conclusion', 'started_at', 'completed_at',
        @{ Name = 'output'; Expression = {
            if ($_.output) { $_.output | Select-Object title, summary, text, annotations_count, annotations_url }
        } }
    )
}
$readRangesScript = Join-Path $PSScriptRoot 'Get-VcpkgReviewReadRanges.ps1'
$root = [System.IO.Path]::GetFullPath($InvestigationRoot)
$runRoot = Join-Path $root ("review-{0}-{1}" -f [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
$sharedRoot = Join-Path $runRoot 'shared'
New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null

$docsCommit = Get-GitHubJson -Endpoint 'repos/MicrosoftDocs/vcpkg-docs/commits/main'
$docsSha = [string]$docsCommit.sha
$guidePath = Join-Path $sharedRoot 'maintainer-guide.md'
$guideEndpoint = "repos/MicrosoftDocs/vcpkg-docs/contents/vcpkg/contributing/maintainer-guide.md?ref=$docsSha"
$guide = Invoke-GitHub -Arguments @($guideEndpoint, '-H', 'Accept: application/vnd.github.raw+json')
Set-Content -LiteralPath $guidePath -Value $guide -Encoding utf8
$guideMetadata = [ordered]@{
    path = $guidePath
    sourceUrl = "https://github.com/MicrosoftDocs/vcpkg-docs/blob/$docsSha/vcpkg/contributing/maintainer-guide.md"
    commit = $docsSha
    retrievedAt = [datetime]::UtcNow.ToString('o')
    sha256 = (Get-FileHash -LiteralPath $guidePath -Algorithm SHA256).Hash
    readRanges = @(& $readRangesScript -Path $guidePath)
}
Write-Json -Path (Join-Path $sharedRoot 'maintainer-guide.json') -Value $guideMetadata

$query = $null
if (-not $PrNumber) {
    $query = "repo:microsoft/vcpkg is:pr is:open draft:false updated:>=$($UpdatedSince.ToString('yyyy-MM-dd'))"
    $endpoint = "search/issues?q=$([uri]::EscapeDataString($query))&per_page=100"
    $search = Get-GitHubJson -Endpoint $endpoint
    if ($search.incomplete_results -or $search.total_count -gt 1000) {
        throw "GitHub search is incomplete or exceeds its 1000-result limit; narrow UpdatedSince."
    }
    $candidates = @(Get-GitHubPages -Endpoint $endpoint -ItemsProperty 'items')
    if ($candidates.Count -ne $search.total_count) {
        throw "Candidate count changed during pagination; rerun evidence collection."
    }
    $PrNumber = @($candidates | ForEach-Object { [int]$_.number })
}

$results = @(
    foreach ($number in @($PrNumber | Sort-Object -Unique)) {
        $evidenceRoot = Join-Path (Join-Path $runRoot "pr-$number") 'evidence'
        $rawRoot = Join-Path $evidenceRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null
        try {
            $endpoint = "repos/microsoft/vcpkg/pulls/$number"
            $pr = Get-GitHubJson -Endpoint $endpoint
            Write-Json -Path (Join-Path $rawRoot 'pr.json') -Value $pr
            $summary = $pr | Select-Object number, title, body, $author, $url, state, draft, created_at, updated_at, changed_files,
                @{ Name = 'head'; Expression = { $_.head | Select-Object sha, ref, $repository } },
                @{ Name = 'base'; Expression = { $_.base | Select-Object sha, ref, $repository } }
            Write-Json -Path (Join-Path $evidenceRoot 'pr-summary.json') -Value $summary
            $files = @(Get-GitHubPages -Endpoint "$endpoint/files?per_page=100")
            if ($files.Count -ne $pr.changed_files) {
                throw "Changed-file list is incomplete (GitHub caps this endpoint at 3000 files)."
            }
            Write-Json -Path (Join-Path $rawRoot 'files.json') -Value $files
            Write-Json -Path (Join-Path $evidenceRoot 'files.json') -Value @($files | Select-Object -Property $projections['files.json'])
            $collections = [ordered]@{
                'comments.json' = "repos/microsoft/vcpkg/issues/$number/comments?per_page=100"
                'reviews.json' = "$endpoint/reviews?per_page=100"
                'review-comments.json' = "$endpoint/comments?per_page=100"
            }
            foreach ($entry in $collections.GetEnumerator()) {
                $items = @(Get-GitHubPages -Endpoint $entry.Value)
                Write-Json -Path (Join-Path $rawRoot $entry.Key) -Value $items
                Write-Json -Path (Join-Path $evidenceRoot $entry.Key) -Value @($items | Select-Object -Property $projections[$entry.Key])
            }
            $headSha = [string]$pr.head.sha
            $baseSha = [string]$pr.base.sha
            $checks = @(Get-GitHubPages -Endpoint "repos/microsoft/vcpkg/commits/$headSha/check-runs?per_page=100" -ItemsProperty 'check_runs')
            Write-Json -Path (Join-Path $rawRoot 'checks.json') -Value $checks
            Write-Json -Path (Join-Path $evidenceRoot 'checks.json') -Value @($checks | Select-Object -Property $projections['checks.json'])
            $diff = Invoke-GitHub -Arguments @($endpoint, '-H', 'Accept: application/vnd.github.diff')
            Set-Content -LiteralPath (Join-Path $evidenceRoot 'pr.diff') -Value $diff -Encoding utf8
            $current = Get-GitHubJson -Endpoint $endpoint
            if ($current.head.sha -ne $headSha -or $current.base.sha -ne $baseSha) {
                throw "PR head or base changed during acquisition; rerun evidence collection."
            }
            $ports = @($files | ForEach-Object {
                $paths = @($_.filename)
                $previous = $_.PSObject.Properties['previous_filename']
                if ($previous) { $paths += $previous.Value }
                foreach ($path in $paths) {
                    if ($path -match '^ports/([^/]+)/') { $Matches[1] }
                }
            } | Sort-Object -Unique)
            [pscustomobject]@{
                number = $number
                status = 'collected'
                title = $pr.title
                url = $pr.html_url
                headSha = $headSha
                baseSha = $baseSha
                ports = $ports
                evidenceRoot = $evidenceRoot
                collectedAt = [datetime]::UtcNow.ToString('o')
                error = $null
            }
        } catch {
            Write-Warning "Evidence collection failed for PR #${number}: $($_.Exception.Message)"
            [pscustomobject]@{
                number = $number
                status = 'failed'
                evidenceRoot = $evidenceRoot
                error = $_.Exception.Message
            }
        }
    }
)
$competition = @(
    $members = foreach ($result in $results | Where-Object status -eq 'collected') {
        foreach ($port in $result.ports) { [pscustomobject]@{ port = $port; number = $result.number } }
    }
    $members | Group-Object port | Where-Object Count -gt 1 | ForEach-Object {
        [pscustomobject]@{ port = $_.Name; prs = @($_.Group.number | Sort-Object) }
    }
)
$manifestPath = Join-Path $runRoot 'evidence-manifest.json'
Write-Json -Path $manifestPath -Value ([ordered]@{
    schemaVersion = 1
    runRoot = $runRoot
    query = $query
    maintainerGuide = $guideMetadata
    prs = $results
    competition = $competition
})
[pscustomobject]@{
    manifestPath = $manifestPath
    collected = @($results | Where-Object status -eq 'collected').Count
    failed = @($results | Where-Object status -eq 'failed').Count
}
