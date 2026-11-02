#requires -Version 5.1
# BW4k7b: revisit exact old Attachment1K without mutating Outlook, PST, journal or claims.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7b requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7bSemanticIntegrity265.ps1')
$stage='Independent exact previous BW4k7a read-only source review'
try{
    $opts=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourcePst=$SourcePst
        ExpectedProfileName=$ExpectedProfileName
    }
    $readOnly=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7aAttachmentSizeDriftReview.ps1') @opts
    $stage='Apply SEM-001 exact original Attachment1K content policy with no size acceptance'
    Get-OPA265BW4k7bSourceSemanticVerdict -Report $readOnly
}catch{
    throw ('BW4k7b STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. Read-only semantic review cannot issue Move or Claim permissions.')
}
