# CI/build-only manifest validation. No Outlook or runtime PST access.
# Independent output statements avoid PowerShell 5.1's surprising array
# expression parsing when combining concatenation, commas and parentheses.
function Get-OPARequiredManifestLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Build,
        [Parameter(Mandatory=$true)][string]$ApplicationVersion,
        [Parameter(Mandatory=$true)][string]$TransactionSchemaVersion,
        [Parameter(Mandatory=$true)][string]$DuplicateIndexSchemaVersion
    )
    "Build: $Build"
    "Application: $ApplicationVersion"
    "Transaction schema: $TransactionSchemaVersion"
    "DuplicateIndex schema: $DuplicateIndexSchemaVersion"
}

function Assert-OPABuildManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Build,
        [Parameter(Mandatory=$true)][string]$ApplicationVersion,
        [Parameter(Mandatory=$true)][string]$TransactionSchemaVersion,
        [Parameter(Mandatory=$true)][string]$DuplicateIndexSchemaVersion
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }
    # Get-Content, WITHOUT -Raw, emits one string per line for LF and CRLF.
    # Explicit UTF8 works with and without a BOM on Windows PowerShell 5.1.
    $actualLines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)
    $requiredLines = @(Get-OPARequiredManifestLines -Build $Build `
        -ApplicationVersion $ApplicationVersion `
        -TransactionSchemaVersion $TransactionSchemaVersion `
        -DuplicateIndexSchemaVersion $DuplicateIndexSchemaVersion)
    if ($requiredLines.Count -ne 4) {
        throw "Manifest validator error: expected 4 separate version lines; got $($requiredLines.Count)."
    }
    foreach ($expected in $requiredLines) {
        $matches = @($actualLines | Where-Object { [string]$_ -ceq [string]$expected })
        if ($matches.Count -ne 1) {
            throw ("Manifest version mismatch: '{0}' (matching lines: {1})" -f $expected,$matches.Count)
        }
    }
    return $true
}
