#requires -Version 5.1
# ARCH3r: completed real ARCH3q historical checkpoint audit (NO writes)
# or ten fake-only TEMP messages through ORIGINAL semantic/journal/index.
# This script NEVER invokes MailItem.Move or production Archive/Resume/Auto.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Audit','Synthetic10')][string]$Mode='Plan',
    [string]$RunId='',
    [string]$IntentSha256='',
    [string]$JournalSha256='',
    [string]$ReviewSha256='',
    [string]$CommitClaimSha256='',
    [string]$CommitSealSha256='',
    [ValidateSet('None','DuplicateSource','DuplicateDestination','HtmlDrift','AttachmentDrift','ProviderUnknown','AfterClaimBeforeProvider','AfterJournalReconciled','AfterIndexAppend')][string]$InjectFault='None',
    [ValidateRange(1,10)][int]$FaultAt=4,
    [string]$SyntheticTempRoot=[IO.Path]::GetTempPath()
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3r requires Windows PowerShell 5.1; no real Outlook COM is used.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3rTenItemSyntheticIntegration.ps1')
if($Mode -ceq 'Synthetic10'){
    if($RunId -or $IntentSha256 -or $JournalSha256 -or $ReviewSha256 -or $CommitClaimSha256 -or $CommitSealSha256){
        throw 'ARCH3r Synthetic10 must not receive operator real completed-pilot RunId or evidence SHA values.'
    }
    Invoke-OPA265ARCH3rSyntheticTen -InjectFault $InjectFault -FaultAt $FaultAt -SyntheticTempRoot $SyntheticTempRoot
    return
}
if($InjectFault -cne 'None' -or $FaultAt -ne 4 -or $PSBoundParameters.ContainsKey('SyntheticTempRoot')){
    throw 'ARCH3r operator completed-pilot Plan/Audit may not use any synthetic fault-injection settings.'
}
$params=@{Mode=$Mode;RunId=$RunId;IntentSha256=$IntentSha256;JournalSha256=$JournalSha256
    ReviewSha256=$ReviewSha256;CommitClaimSha256=$CommitClaimSha256;CommitSealSha256=$CommitSealSha256}
Get-OPA265ARCH3rCompletedRealCheckpoint @params
