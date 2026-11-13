#requires -Version 5.1
# ARCH3f read-only real POP3 test PST preflight. No COM Move and no PST writes.
# Exact source is operator-designated test PST with real messages.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','Inventory')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [ValidateRange(1,20)][int]$SamplePerFolder=5,
    [ValidateRange(1,128)][int]$MaxFolders=64,
    [ValidateRange(0,120)][int]$OlderThanMonths=0
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3f requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Inventory' -and
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH3f real Outlook Inventory requires PowerShell -STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3fRealTestPstPreflight.ps1')
Invoke-OPA265ARCH3fRealTestPreflight -Mode $Mode -SourcePst $SourcePst -SamplePerFolder $SamplePerFolder -MaxFolders $MaxFolders -OlderThanMonths $OlderThanMonths
