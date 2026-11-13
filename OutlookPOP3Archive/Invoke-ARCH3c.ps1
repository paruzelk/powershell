#requires -Version 5.1
# ARCH3c explicit SYNTHETIC-ONLY disk journal under OS TEMP.
# NEVER opens Outlook, source PST, archive PST, old transaction or index.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','SyntheticWrite','Evidence')][string]$Mode='Plan',
    [string]$SourcePst='',
    [string]$ScratchRoot='',
    [string]$TransactionId='',
    [string]$FinalSealSha256='',
    [switch]$ConfirmSyntheticWrite,
    [ValidateSet('None','PrepareIntent','DestinationReady','SourceWitnessAnchored',
       'MoveClaimed','MoveReturned','IndependentContentVerified','IndexCommitted')]
    [string]$InjectStopAfter='None'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3c synthetic journal requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.Plan.1'
        Status='SyntheticOnlyOriginalOperationJournalAdapterPlanNoPstNoComNoFiles'
        ReusesOriginalArchiveSelectorAndYearPaths=$true
        ReusesOriginalOperationJournal=$true
        OriginalLegacyMailMoverUnmodified=$true
        SyntheticFilesRequireExplicitApproval=$true
        SyntheticWritesRestrictedToOsTemp=$true
        ActualMailItemMoveIntegrated=$false
        LegacyTransactionAndDuplicateIndexWriterIntegrated=$false
        IndependentLiveReconcileIntegrated=$false
        ArchiveResumeAutoRemainClosed=$true
        OutlookContacted=$false;PstOpened=$false;JournalWritten=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
if([string]::IsNullOrWhiteSpace($SourcePst)){
    throw 'ARCH3c requires -SourcePst only as NAME STRING; PST is not opened.'
}
if($Mode -ceq 'SyntheticWrite' -and [string]::IsNullOrWhiteSpace($TransactionId)){
    $TransactionId='ARCH3C-SYNTHETIC-'+[guid]::NewGuid().ToString('N')
}
if($Mode -ceq 'Evidence' -and ([string]::IsNullOrWhiteSpace($TransactionId) -or
   [string]::IsNullOrWhiteSpace($ScratchRoot))){
    throw 'ARCH3c independent evidence requires original synthetic TransactionId and ScratchRoot.'
}
if([string]::IsNullOrWhiteSpace($ScratchRoot)){
    $ScratchRoot=Join-Path ([IO.Path]::GetTempPath()) $TransactionId
}
# Importing original MailMover defines a backward-compatibility alias.
# Suppress only its unrelated Set-Alias WhatIf notice, not the transaction's
# ShouldProcess and not any synthetic disk write.
$originalWhatIfPreference=$WhatIfPreference
try{
    $WhatIfPreference=$false
    . (Join-Path $PSScriptRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
}finally{$WhatIfPreference=$originalWhatIfPreference}
$candidate=[pscustomobject][ordered]@{
    EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'
    ArchiveDate=[datetime]'2020-02-12T12:30:00'
    SourceFolderPath='\\POP3 Store\Входящие'
    FolderName='Входящие'
}
$contract=New-OPA265ARCH3bOperationContract -Candidate $candidate -TransactionId $TransactionId -SourcePst $SourcePst -SourceStoreId 'ARCH3C-SYNTHETIC-STORE-NOT-REAL' -ArchiveGrouping Year
if($Mode -ceq 'Evidence'){
    return Test-OPA265ARCH3cSyntheticEvidence -Contract $contract -ScratchRoot $ScratchRoot -ExternallyPinnedFinalSealSha256 $FinalSealSha256
}
if($WhatIfPreference){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.WhatIf.1'
        Status='SyntheticWriteWhatIfNoPstNoComNoJournalWrites'
        TransactionId=$TransactionId
        ScratchRoot=$ScratchRoot
        WriterPermit=$false
        ProductionReady=$false
    }
}
if(-not $ConfirmSyntheticWrite){throw 'ARCH3c needs -ConfirmSyntheticWrite for isolated synthetic temporary files.'}
if(-not $PSCmdlet.ShouldProcess($ScratchRoot,'Write 7 immutable SYNTHETIC stages and ORIGINAL OperationJournal inside OS TEMP only')){
    throw 'ARCH3c synthetic write not approved.'
}
Invoke-OPA265ARCH3cSyntheticWrite -Contract $contract -ScratchRoot $ScratchRoot -ConfirmSyntheticWrite:$true -InjectStopAfter $InjectStopAfter
