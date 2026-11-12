#requires -Version 5.1
# ARCH3b: read-only compatibility preview for original MailMover API.
# No Outlook COM, no PST read/write, no journal, no actual permits.
[CmdletBinding()]
param(
    [ValidateSet('Plan','SyntheticPreview','SyntheticCrashReview')][string]$Mode='Plan',
    [string]$SourcePst=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3b requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Plan'){
    [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3b.Plan.1'
        Status='ExistingMailMoverPreDestinationOperationContractPlanNoWriter'
        OriginalGroupingAndPstNamingReused=$true
        DurableIntentBeforeDestinationCreationRequired=$true
        OriginalSemanticWitnessBeforeMoveRequired=$true
        PostRestartIndependentReconcileRequired=$true
        IntegrationToLegacyMailMoverNotYetEnabled=$true
        OutlookContacted=$false;PstOpened=$false;JournalWritten=$false
        ArchiveResumeAutoRemainClosed=$true
        WriterPermit=$false;ProductionReady=$false
    }
    return
}
if([string]::IsNullOrWhiteSpace($SourcePst)){
    throw 'ARCH3b examples require -SourcePst as path string only; no PST file is opened.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3bOriginalMoverContract.ps1')
$tx='ARCH3B-SYNTHETIC-READONLY'
$store='ARCH3B-SYNTHETIC-NOT-A-REAL-STORE'
$rows=@(
    [pscustomobject]@{
        EntryID='00000000E1878292411BC64291BD506DCEFD2A3540093C00'
        ArchiveDate=([datetime]'2020-02-12T12:30:00')
        SourceFolderPath='\\POP3 Store\Входящие'
        FolderName='Входящие'
    },
    [pscustomobject]@{
        EntryID='00000000E1878292411BC64291BD506DCEFD2A3520093C00'
        ArchiveDate=([datetime]'2020-12-31T23:50:00')
        SourceFolderPath='\\POP3 Store\Отправленные'
        FolderName='Отправленные'
    },
    [pscustomobject]@{
        EntryID='00000000E1878292411BC64291BD506DCEFD2A3500093C00'
        ArchiveDate=([datetime]'2021-05-01T09:15:00')
        SourceFolderPath='\\POP3 Store\Проекты\Договоры'
        FolderName='Договоры'
    }
)
$preview=New-OPA265ARCH3bBatchPreview -Candidates $rows -TransactionId $tx -SourcePst $SourcePst -SourceStoreId $store -ArchiveGrouping Year
if($Mode -ceq 'SyntheticPreview'){
    $preview
    return
}
$contract=$preview.Items[0]
$stages=@('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed')
$events=New-Object 'System.Collections.Generic.List[object]'
foreach($stage in $stages){
    $events.Add([pscustomobject]@{
        OperationId=[string]$contract.OperationId
        TransactionId=[string]$contract.TransactionId
        Phase=$stage
        SourceWitnessSha256=('a'*64)
        DurablyFlushedBeforeMove=$true
    })|Out-Null
}
$unknown=[pscustomobject]@{
    OperationId=[string]$contract.OperationId
    TransactionId=[string]$contract.TransactionId
    Phase='MoveIndeterminate'
}
$events.Add($unknown)|Out-Null
Test-OPA265ARCH3bPhaseEvidence -Contract $contract -Events @($events.ToArray())
