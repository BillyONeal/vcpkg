[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lines = @(Get-Content -LiteralPath $Path)
if ($lines.Count -eq 0) { throw "Cannot prepare read ranges for an empty guide: $Path" }
$start = 1
$bytes = 0
for ($index = 0; $index -lt $lines.Count; $index++) {
    $lineBytes = [System.Text.Encoding]::UTF8.GetByteCount($lines[$index]) + 2
    if ($lineBytes -gt 18000) { throw "Guide line $($index + 1) exceeds the 18000-byte read budget: $Path" }
    if ($bytes + $lineBytes -gt 18000) {
        [pscustomobject]@{ start = $start; end = $index }
        $start = $index + 1
        $bytes = 0
    }
    $bytes += $lineBytes
}
[pscustomobject]@{ start = $start; end = $lines.Count }
