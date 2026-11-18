# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

<#
.SYNOPSIS
Builds the file list databases consumed by downstream tooling (for example, the vcpkg.io file search).

.DESCRIPTION
Writes two files into OutDir:

* VCPKGDatabase.txt: lines of the form `port:triplet:/path/inside/package`
* VCPKGHeadersDatabase.txt: lines of the form `port:triplet:relative/header/path` for each file under `/include/`

In InfoDir mode, the lists are built from vcpkg's installed `.list` files.

In BinaryCache mode (used for pull requests), the lists are built by downloading the binary cache ZIP for each
entry in pr-hashes.json whose port was changed relative to TargetBranch.

.PARAMETER OutDir
The directory to which the databases are written.

.PARAMETER InfoDir
The `installed/vcpkg/info` directory containing vcpkg-generated `.list` files.

.PARAMETER PrHashes
The pr-hashes.json file produced by `vcpkg ci --output-hashes`.

.PARAMETER BinaryCacheUrl
The URL of the binary cache container, without a SAS token. For example,
https://vcpkgbinarycachewus.blob.core.windows.net/cache

.PARAMETER BinaryCacheSas
The SAS token used to read from BinaryCacheUrl, without a leading '?'.

.PARAMETER TargetBranch
The branch against which changed ports are determined.
#>

[CmdletBinding(DefaultParameterSetName = 'InfoDir')]
Param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutDir,
    [Parameter(Mandatory = $true, ParameterSetName = 'InfoDir')]
    [ValidateNotNullOrEmpty()]
    [string]$InfoDir,
    [Parameter(Mandatory = $true, ParameterSetName = 'BinaryCache')]
    [ValidateNotNullOrEmpty()]
    [string]$PrHashes,
    [Parameter(Mandatory = $true, ParameterSetName = 'BinaryCache')]
    [ValidateNotNullOrEmpty()]
    [string]$BinaryCacheUrl,
    [Parameter(Mandatory = $true, ParameterSetName = 'BinaryCache')]
    [ValidateNotNullOrEmpty()]
    [string]$BinaryCacheSas,
    [Parameter(ParameterSetName = 'BinaryCache')]
    [string]$TargetBranch = 'origin/master'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$includePrefix = '/include/'
$dbLines = [System.Collections.Generic.List[string]]::new()
$headerLines = [System.Collections.Generic.List[string]]::new()

function Add-FileEntry([string]$Package, [string]$FilePath) {
    $dbLines.Add("${Package}:$FilePath")
    if ($FilePath.StartsWith($includePrefix, [System.StringComparison]::Ordinal)) {
        $headerLines.Add("${Package}:$($FilePath.Substring($includePrefix.Length))")
    }
}

function Write-Databases {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    foreach ($entry in @(@('VCPKGDatabase.txt', $dbLines), @('VCPKGHeadersDatabase.txt', $headerLines))) {
        $content = ''
        if ($entry[1].Count -ne 0) {
            $content = ($entry[1] -join "`n") + "`n"
        }

        [System.IO.File]::WriteAllText((Join-Path $OutDir $entry[0]), $content, $utf8)
    }

    Write-Host "Wrote $(Join-Path $OutDir 'VCPKGDatabase.txt') and $(Join-Path $OutDir 'VCPKGHeadersDatabase.txt')"
}

if ($PSCmdlet.ParameterSetName -eq 'InfoDir') {
    foreach ($file in Get-ChildItem -LiteralPath $InfoDir -File) {
        if ($file.Name.StartsWith('.')) {
            continue
        }

        # Info files are named <port>_<version>_<triplet>.list
        $components = $file.Name.Split('_')
        $package = $components[0] + ':' + $components[2].Replace('.list', '')
        foreach ($rawLine in [System.IO.File]::ReadAllLines($file.FullName)) {
            $line = $rawLine.Trim()
            if ($line.Length -eq 0 -or $line.EndsWith('/')) {
                continue
            }

            # Remove the leading triplet directory
            $slash = $line.IndexOf('/')
            if ($slash -ge 0) {
                $line = $line.Substring($slash)
            }

            Add-FileEntry -Package $package -FilePath $line
        }
    }

    Write-Databases
    exit 0
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$prHashEntries = Get-Content -LiteralPath $PrHashes -Raw | ConvertFrom-Json -NoEnumerate
if ($prHashEntries -isnot [array]) {
    throw "Invalid pr-hashes.json format: expected a top-level JSON array (vcpkg-tool output)."
}

$mergeBase = (& git merge-base $TargetBranch HEAD)
if ($LASTEXITCODE -ne 0) {
    throw "git merge-base $TargetBranch HEAD failed; this is fatal in binary cache mode."
}

$repoRoot = (& git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0) {
    throw "git rev-parse --show-toplevel failed."
}

$changedFiles = @(& git -C $repoRoot diff --name-only "$($mergeBase.Trim())...HEAD" -- ports/)
if ($LASTEXITCODE -ne 0) {
    throw "git diff failed; this is fatal in binary cache mode."
}

$changedPorts = [System.Collections.Generic.HashSet[string]]::new()
foreach ($changedFile in $changedFiles) {
    if ($changedFile -match '^ports/([^/]+)') {
        $changedPorts.Add($Matches[1]) | Out-Null
    }
}

if ($changedPorts.Count -eq 0) {
    Write-Host "git diff found no changed ports under ports/ for range $mergeBase...HEAD."
    Write-Databases
    exit 0
}

$baseUrl = $BinaryCacheUrl.TrimEnd('/', '\')
$sas = $BinaryCacheSas.TrimStart('?')
$tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "vcpkg-file-list-$PID.zip"
try {
    foreach ($item in $prHashEntries) {
        if (-not $changedPorts.Contains($item.name)) {
            continue
        }

        if ($item.abi -notmatch '^[a-f0-9]{64}$') {
            throw "Invalid ABI format in pr-hashes.json for port $($item.name): $($item.abi)"
        }

        $blobUrl = "$baseUrl/$($item.abi).zip"
        Write-Host "Downloading $blobUrl for $($item.name):$($item.triplet)..."
        try {
            Invoke-WebRequest -Uri "${blobUrl}?$sas" -OutFile $tempZip -UseBasicParsing
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
            try {
                foreach ($zipEntry in $zip.Entries) {
                    $entryName = '/' + $zipEntry.FullName.Replace('\', '/')
                    if ($entryName.EndsWith('/') -or $entryName -eq '/BUILD_INFO' -or $entryName -eq '/CONTROL') {
                        continue
                    }

                    Add-FileEntry -Package "$($item.name):$($item.triplet)" -FilePath $entryName
                }
            } finally {
                $zip.Dispose()
            }
        } catch {
            Write-Warning "Failed to download or process $blobUrl for $($item.name): $($_.Exception.Message)"
        }
    }
} finally {
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
}

Write-Databases
