#requires -Version 5.1
# ARCH3a: read-only reuse audit of EXISTING OutlookPOP3Archive.
# No COM, no Save/Move/Copy/Delete, no PST mount, no journal writes.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Audit','RoutingExamples')][string]$Mode='Audit',
    [string]$SourcePst=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3a requires native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Diagnostics/ARCH3aLegacyIntegrationAudit.ps1')
if($Mode -ceq 'Plan'){
    [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3a.Plan.1'
        Status='ReadOnlyOriginalArchiverIntegrationPlanNoOutlookNoPstOrJournalWrites'
        ProjectRoot=$PSScriptRoot
        OriginalYearGroupingToBeReused=$true
        OriginalPop3FolderTraversalToBeReused=$true
        OriginalMailMoverDestinationToBeReused=$true
        NewIndependentArchiverForbidden=$true
        ArchiveResumeAutoRemainClosed=$true
        WriterPermit=$false
        ProductionReady=$false
    }
}elseif($Mode -ceq 'Audit'){
    Get-OPA265ARCH3aIntegrationAudit -ProjectRoot $PSScriptRoot
}else{
    if([string]::IsNullOrWhiteSpace($SourcePst)){
        throw 'ARCH3a RoutingExamples needs -SourcePst for existing source naming, path string only (PST never opened).'
    }
    Get-OPA265ARCH3aExistingRoutingExamples -ProjectRoot $PSScriptRoot -SourcePst $SourcePst
}
