[CmdletBinding(PositionalBinding=$False)]
Param(
    [Parameter(Mandatory=$True)]
    [String]$DiffFile
)

Start-Process -FilePath 'git' -ArgumentList 'diff' `
    -NoNewWindow -Wait `
    -RedirectStandardOutput $DiffFile
if (0 -ne (Get-Item -LiteralPath $DiffFile).Length)
{
    $msg = @(
        'The formatting of the files in the repo were not what we expected,',
        'or the documentation was not regenerated.',
        'Please access the diff from format.diff in the build artifacts,'
        'and apply the patch with `git apply`'
    )
    if (-Not [string]::IsNullOrEmpty($env:GITHUB_STEP_SUMMARY))
    {
        $diff = Get-Content -LiteralPath $DiffFile -Raw
        # Job summaries are limited to 1 MiB per step.
        if ($diff.Length -lt 900KB)
        {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value @(
                '## Formatting differences',
                '',
                'Apply this patch with `git apply`, or download it from the format.diff artifact.',
                '',
                '````diff',
                $diff.TrimEnd(),
                '````'
            )
        }
    }

    Write-Error ($msg -join "`n")
    throw
}