#requires -Version 5.1
# ARCH3g original annual PST collision gate: Plan (disk only), Audit (real POP3 read-only).
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$SourceEntryId,
    [ValidateRange(1900,2100)][int]$ArchiveYear=2020
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3g requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Audit' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH3g Audit requires PowerShell -STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3gExistingArchiveCollisionGate.ps1')
Invoke-OPA265ARCH3gExistingArchiveGate -Mode $Mode -SourcePst $SourcePst -SourceEntryId $SourceEntryId -ArchiveYear $ArchiveYear
