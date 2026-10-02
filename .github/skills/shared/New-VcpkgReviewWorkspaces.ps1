[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$CallerRoot,

    [Parameter(Mandatory = $true)]
    [string]$ReviewsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string[]]$Arguments)
    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed ($LASTEXITCODE): $($Arguments -join ' ')"
    }
    return ($output -join "`n")
}

$caller = [System.IO.Path]::GetFullPath($CallerRoot)
$reviews = [System.IO.Path]::GetFullPath($ReviewsRoot)
$manifestFile = [System.IO.Path]::GetFullPath($ManifestPath)
$manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw "Unsupported evidence manifest schema." }
$repositoryRoot = Invoke-Git -Arguments @('-C', $caller, 'rev-parse', '--show-toplevel')
if ([System.IO.Path]::GetFullPath($repositoryRoot) -ne $caller.TrimEnd('\', '/')) {
    throw "CallerRoot must be the repository root."
}
$executableName = if ($env:OS -eq 'Windows_NT') { 'vcpkg.exe' } else { 'vcpkg' }
$executable = Join-Path $caller $executableName
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Missing caller executable: $executable"
}
$guidePath = Join-Path $caller '.github\skills\shared\review-vcpkg-pr-guide.md'
if (-not (Test-Path -LiteralPath $guidePath -PathType Leaf)) { throw "Missing shared review guide: $guidePath" }
$guideSnapshot = Join-Path (Join-Path $manifest.runRoot 'shared') 'review-vcpkg-pr-guide.md'
Copy-Item -LiteralPath $guidePath -Destination $guideSnapshot
$guideReadRanges = @(& (Join-Path $PSScriptRoot 'Get-VcpkgReviewReadRanges.ps1') -Path $guideSnapshot)
$workers = @(
    foreach ($pr in $manifest.prs) {
        if ($pr.status -ne 'collected') {
            [pscustomobject]@{ number = $pr.number; status = 'failed'; error = $pr.error }
            continue
        }
        $workerRoot = Join-Path $manifest.runRoot "pr-$($pr.number)"
        $workspace = Join-Path $workerRoot 'workspace'
        try {
            if (Test-Path -LiteralPath $workspace) { throw "Workspace already exists: $workspace" }
            Invoke-Git -Arguments @('-C', $caller, 'fetch', '--no-tags', 'https://github.com/microsoft/vcpkg.git', "refs/pull/$($pr.number)/head") | Out-Null
            $fetched = Invoke-Git -Arguments @('-C', $caller, 'rev-parse', 'FETCH_HEAD')
            if ($fetched -ne $pr.headSha) { throw "PR head changed since evidence collection; recollect before reviewing." }
            Invoke-Git -Arguments @('-C', $caller, 'fetch', '--no-tags', 'https://github.com/microsoft/vcpkg.git', $pr.baseSha) | Out-Null
            Invoke-Git -Arguments @('-C', $caller, 'worktree', 'add', '--detach', $workspace, $pr.headSha) | Out-Null
            Copy-Item -LiteralPath $executable -Destination (Join-Path $workspace $executableName)
            $checkedOut = Invoke-Git -Arguments @('-C', $workspace, 'rev-parse', 'HEAD')
            if ($checkedOut -ne $pr.headSha) { throw "Workspace revision does not match evidence." }
            $artifacts = Join-Path $workerRoot 'artifacts'
            New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
            [pscustomobject]@{
                number = $pr.number
                status = 'ready'
                workspace = $workspace
                investigationRoot = $artifacts
                reportDir = Join-Path $reviews "pr-$($pr.number)"
                headSha = $pr.headSha
                baseSha = $pr.baseSha
                evidenceRoot = $pr.evidenceRoot
                guidePath = $guideSnapshot
                guideReadRanges = $guideReadRanges
                maintainerGuidePath = $manifest.maintainerGuide.path
                maintainerGuideReadRanges = $manifest.maintainerGuide.readRanges
                maintainerGuideMetadataPath = Join-Path (Split-Path $manifest.maintainerGuide.path) 'maintainer-guide.json'
                downloads = $env:VCPKG_DOWNLOADS
                error = $null
            }
        } catch {
            Write-Warning "Workspace preparation failed for PR #$($pr.number): $($_.Exception.Message)"
            [pscustomobject]@{ number = $pr.number; status = 'failed'; error = $_.Exception.Message }
        }
    }
)
$workersPath = Join-Path $manifest.runRoot 'workers.json'
[ordered]@{
    schemaVersion = 1
    evidenceManifestPath = $manifestFile
    reviewsRoot = $reviews
    workers = $workers
} | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $workersPath -Encoding utf8
[pscustomobject]@{
    workersPath = $workersPath
    ready = @($workers | Where-Object status -eq 'ready').Count
    failed = @($workers | Where-Object status -eq 'failed').Count
}
