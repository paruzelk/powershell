#requires -Version 5.1
# ARCH2d3 CI-only synthetic fault matrix: never opens Outlook or any PST,
# never executes ARCH2d MoveBatch, and never modifies real archive evidence.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Simulate')][string]$Mode='Plan',
    [string]$SandboxRoot=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH2d3 requires Windows PowerShell 5.1 for fidelity with original writer.'
}
. (Join-Path $PSScriptRoot 'Core/Diagnostics/ARCH2d3FaultSimulator.ps1')
if($Mode -eq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d3.SyntheticPlan.1'
        Status='ReadOnlyFaultMatrixPlanNoFileWrites'
        Cases=57
        FaultModels=19
        InjectAt=@(1,5,10)
        ActualOutlookContacted=$false
        ActualPstReadOrWritten=$false
        HistoricalARCH2c4AndARCH2dEvidenceModified=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
if([string]::IsNullOrWhiteSpace($SandboxRoot)){
    throw 'ARCH2d3 Simulate needs an EXISTING isolated scratch SandboxRoot, not a PST or Outlook data directory.'
}
Invoke-OPA265ARCH2d3SyntheticMatrix -SandboxRoot $SandboxRoot
