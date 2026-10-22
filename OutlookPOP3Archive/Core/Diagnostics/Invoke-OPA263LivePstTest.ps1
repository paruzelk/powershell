#requires -Version 5.1
<#
.SYNOPSIS
    Disposable real-Outlook COM integration test for 2.6.3 read-only move reconciliation.
.DESCRIPTION
    Creates TWO NEW PSTs in a unique temporary directory, copies one
    existing mail from an explicitly selected test donor PST, and performs
    a controlled FIRST Move on the cloned message. The original donor
    message is never moved/deleted. A Copy operation temporarily writes a
    duplicate in its donor folder before moving the duplicate to the new
    disposable PST; an abrupt failure can leave this extra copy behind.
    No retry/reconciliation decision is made automatically. All evidence
    and both disposable PST files remain on disk for inspection.
.EXAMPLE
    .\Core\Diagnostics\Invoke-OPA263LivePstTest.ps1 -SeedPstPath 'C:\Test\seed.pst' -Execute
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SeedPstPath,
    [ValidateRange(1,5000)][int]$MaxScanItems = 500,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
if (-not $Execute) {
    throw 'No PSTs changed. Pass -Execute to explicitly authorize disposable Outlook COM test operations.'
}
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Outlook COM integration requires Windows PowerShell 5.1 -STA.'
}

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Core/Runtime/ComManager.ps1')
. (Join-Path $root 'Core/Archive/ArchiveSelector.ps1')
. (Join-Path $root 'Core/Archive/OperationJournal.ps1')
. (Join-Path $root 'Core/Archive/MoveReconciliation.ps1')

function Get-OPA263MountedStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $expected = [IO.Path]::GetFullPath($Path)
    $stores = $Namespace.Stores
    for ($i=1; $i -le [int]$stores.Count; $i++) {
        $store = $stores.Item($i)
        try {
            $candidate = [string]$store.FilePath
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and
                [IO.Path]::GetFullPath($candidate) -ieq $expected) {
                return $store
            }
        }
        catch {}
    }
    throw "Mounted Outlook PST not found: $expected"
}

function Add-OPA263Outcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ExpectedStatus,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Output
    )
    $ok = ([string]$Result.Status -ceq $ExpectedStatus -and
        -not [bool]$Result.AutomaticRetryAllowed -and
        -not [bool]$Result.ProvenMoved -and
        [bool]$Result.RequiresManualReview)
    [void]$Output.Add([pscustomobject]@{
        Scenario=$Name; Expected=$ExpectedStatus
        Actual=[string]$Result.Status
        Passed=$ok; Reason=[string]$Result.Reason
        SourceMatches=[int]$Result.SourceMatches
        DestinationMatches=[int]$Result.DestinationMatches
    })
    $label = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0} {1}: {2} (expected {3})" -f $label,$Name,[string]$Result.Status,$ExpectedStatus)
    if (-not $ok) {
        throw ("Live PST reconciliation test '{0}' failed: {1}" -f $Name,[string]$Result.Reason)
    }
}

function Invoke-OPA263Review {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JournalPath,
        [Parameter(Mandatory=$true)][string]$OperationId,
        [Parameter(Mandatory=$true)][object]$SourceFolder,
        [Parameter(Mandatory=$true)][object]$DestinationFolder,
        [Parameter(Mandatory=$true)][object]$SourceStore,
        [Parameter(Mandatory=$true)][object]$DestinationStore,
        [Parameter(Mandatory=$true)][string]$ArchivePst
    )
    return (Invoke-OPAReadOnlyInterruptedMoveReview -JournalPath $JournalPath -OperationId $OperationId `
        -SourceFolder $SourceFolder -DestinationFolder $DestinationFolder `
        -SourceStoreId ([string]$SourceStore.StoreID) `
        -SourceFolderPath ([string]$SourceFolder.FolderPath) `
        -DestinationStoreId ([string]$DestinationStore.StoreID) `
        -TargetFolderPath ([string]$DestinationFolder.FolderPath) `
        -ArchivePst $ArchivePst)
}

$seedPath = [IO.Path]::GetFullPath($SeedPstPath)
if (-not [IO.File]::Exists($seedPath) -or
    [IO.Path]::GetExtension($seedPath) -ine '.pst') {
    throw "SeedPstPath must identify an existing .pst file: $seedPath"
}
$runId = [guid]::NewGuid().ToString('N')
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('OPA263-Live-' + $runId)
$sourcePst = Join-Path $testDir 'OPA263-Source.pst'
$archivePst = Join-Path $testDir 'OPA263-Archive.pst'
$journalPath = Join-Path $testDir ('live-' + $runId + '.operations.jsonl')
$reportPath = Join-Path $testDir 'report.json'
$transactionId = 'live-' + $runId
$operationId = [guid]::NewGuid().ToString('D')
$results = New-Object 'System.Collections.Generic.List[object]'
$failure = ''
$stage = 'Initializing'
$duplicateDiagnostics = $null

[void][IO.Directory]::CreateDirectory($testDir)
Write-Host ("Test directory: {0}" -f $testDir)
Write-Host 'No existing PST messages will be moved or deleted.'
Write-Host 'The selected donor PST may transiently receive one extra copied mail before staging.'

$outlook = $null; $ns = $null; $donorStore = $null; $donorFolder = $null
$sourceStore = $null; $archiveStore = $null
$sourceFolder = $null; $archiveFolder = $null
$original = $null; $temporaryCopy = $null; $staged = $null
try {
    $stage = 'Connect Outlook'
    # Never create Outlook or select a different profile implicitly.
    $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns = $outlook.GetNamespace('MAPI')
    $donorStore = Get-OPA263MountedStore -Namespace $ns -Path $seedPath
    $donorFolder = $donorStore.GetDefaultFolder(6) # olFolderInbox
    if ($null -eq $donorFolder) { throw 'Test donor Inbox not available.' }

    $stage = 'Select donor MailItem'
    $donorItems = $donorFolder.Items
    $count = [Math]::Min([int]$donorItems.Count,$MaxScanItems)
    for ($i=1; $i -le $count; $i++) {
        $candidate = $null
        try {
            $candidate = $donorItems.Item($i)
            if ($null -eq $candidate -or [int]$candidate.Class -ne 43) { continue }
            $id = [string](Get-OPAInternetMessageId -Item $candidate)
            if ([string]::IsNullOrWhiteSpace($id) -or
                [string]::IsNullOrWhiteSpace([string]$candidate.Subject) -or
                [string]::IsNullOrWhiteSpace([string]$candidate.SenderEmailAddress) -or
                [long]$candidate.Size -le 0) {
                continue
            }
            $original = $candidate
            $candidate = $null
            break
        }
        catch {}
        finally { if ($null -ne $candidate) { Release-OPAComObject -Object $candidate } }
    }
    if ($null -eq $original) {
        throw ("No suitable Inbox MailItem with complete InternetMessageId/Subject/Sender/Size among first {0} items." -f $count)
    }

    $stage = 'Create disposable PSTs'
    $ns.AddStoreEx($sourcePst,2) # olStoreUnicode
    $ns.AddStoreEx($archivePst,2)
    $sourceStore = Get-OPA263MountedStore -Namespace $ns -Path $sourcePst
    $archiveStore = Get-OPA263MountedStore -Namespace $ns -Path $archivePst
    if ([string]$sourceStore.StoreID -ceq [string]$archiveStore.StoreID) {
        throw 'Disposable source/destination StoreIDs unexpectedly identical.'
    }
    $sourceRoot = $sourceStore.GetRootFolder()
    $archiveRoot = $archiveStore.GetRootFolder()
    $sourceFolder = $sourceRoot.Folders.Add('OPA263_Source_' + $runId)
    $archiveFolder = $archiveRoot.Folders.Add('OPA263_Archive_' + $runId)

    $stage = 'Stage test-only cloned MailItem'
    $temporaryCopy = $original.Copy()
    if ($null -eq $temporaryCopy) { throw 'Outlook MailItem.Copy returned null.' }
    $staged = $temporaryCopy.Move($sourceFolder)
    if ($null -eq $staged) { throw 'Outlook MailItem.Move into disposable source returned null.' }
    $sourceEntryId = [string]$staged.EntryID
    $messageId = [string](Get-OPAInternetMessageId -Item $staged)
    $subject = [string]$staged.Subject
    $sender = [string]$staged.SenderEmailAddress
    $size = [long]$staged.Size
    if ([string]::IsNullOrWhiteSpace($sourceEntryId) -or
        [string]::IsNullOrWhiteSpace($messageId) -or
        [string]::IsNullOrWhiteSpace($subject) -or
        [string]::IsNullOrWhiteSpace($sender) -or $size -le 0) {
        throw 'Cloned mail lost mandatory fingerprint metadata during staging.'
    }
    $temporaryCopy = $null
    Release-OPAComObject -Object $staged
    $staged = $null
    Release-OPAComObject -Object $original
    $original = $null

    $stage = 'Persist MailMove Intent'
    # The move that follows this Intent is the FIRST controlled Move from
    # disposable source to disposable destination, never an automatic retry.
    Write-OPAOperationJournalEvent -Path $journalPath -TransactionId $transactionId `
        -OperationId $operationId -Sequence 1 -Phase Intent -OperationKind MailMove `
        -SourceEntryId $sourceEntryId -SourceStoreId ([string]$sourceStore.StoreID) `
        -SourceFolderPath ([string]$sourceFolder.FolderPath) `
        -TargetFolderPath ([string]$archiveFolder.FolderPath) -ArchivePst $archivePst `
        -InternetMessageId $messageId -Subject $subject -Sender $sender -Size $size | Out-Null

    $stage = 'Read-only SourceOnly'
    $r = Invoke-OPA263Review -JournalPath $journalPath -OperationId $operationId `
        -SourceFolder $sourceFolder -DestinationFolder $archiveFolder `
        -SourceStore $sourceStore -DestinationStore $archiveStore -ArchivePst $archivePst
    Add-OPA263Outcome -Name 'Before first Move' -ExpectedStatus SourceOnly -Result $r -Output $results

    $stage = 'First controlled Move'
    $mail = $ns.GetItemFromID($sourceEntryId,[string]$sourceStore.StoreID)
    if ($null -eq $mail) { throw 'Cloned mail disappeared from disposable source before Move.' }
    $moved = $mail.Move($archiveFolder)
    if ($null -eq $moved) { throw 'First controlled Move returned null; preserve journal.' }
    $movedId = [string]$moved.EntryID
    $afterMoveSize = [long]$moved.Size
    if ([string]::IsNullOrWhiteSpace($movedId)) { throw 'Moved MailItem has no EntryID.' }
    Write-Host ("Size before Move: {0}; after Move: {1} bytes" -f $size,$afterMoveSize)
    Release-OPAComObject -Object $mail
    Release-OPAComObject -Object $moved

    # Intent is deliberately left without a Completed event to simulate a
    # process crash in the window after COM Move and before completion flush.
    $stage = 'Read-only DestinationCandidate'
    $r = Invoke-OPA263Review -JournalPath $journalPath -OperationId $operationId `
        -SourceFolder $sourceFolder -DestinationFolder $archiveFolder `
        -SourceStore $sourceStore -DestinationStore $archiveStore -ArchivePst $archivePst
    Add-OPA263Outcome -Name 'After Move without Completed' `
        -ExpectedStatus DestinationCandidate -Result $r -Output $results

    $stage = 'Create simulated duplicate in source'
    $destinationMail = $ns.GetItemFromID($movedId,[string]$archiveStore.StoreID)
    $backCopy = $destinationMail.Copy()
    $backMoved = $backCopy.Move($sourceFolder)
    if ($null -eq $backMoved) { throw 'Could not stage duplicate in disposable source.' }
    Release-OPAComObject -Object $destinationMail
    Release-OPAComObject -Object $backMoved

    $stage = 'Read-only BothPresent'
    $r = Invoke-OPA263Review -JournalPath $journalPath -OperationId $operationId `
        -SourceFolder $sourceFolder -DestinationFolder $archiveFolder `
        -SourceStore $sourceStore -DestinationStore $archiveStore -ArchivePst $archivePst
    Add-OPA263Outcome -Name 'Source and destination match' `
        -ExpectedStatus BothPresent -Result $r -Output $results

    $stage = 'Create second destination duplicate'
    # Outlook MailItem.Copy() may yield a new, not-yet-persisted item or a
    # clone whose actual parent differs from the expected folder. The first
    # live run revealed one destination match rather than two, despite Copy()
    # returning an object. Do NOT assume Copy() proves an on-disk duplicate.
    # Move the COPY into our disposable source and then back to the disposable
    # archive, exactly as tested by the successful BothPresent scenario.
    $destinationMail = $ns.GetItemFromID($movedId,[string]$archiveStore.StoreID)
    if ($null -eq $destinationMail) { throw 'Original archived test mail unavailable.' }
    $duplicate = $destinationMail.Copy()
    if ($null -eq $duplicate) { throw 'Cannot create test duplicate in disposable archive.' }
    $duplicateInSource = $duplicate.Move($sourceFolder)
    if ($null -eq $duplicateInSource) { throw 'Could not stage second test duplicate in disposable source.' }
    $duplicateInArchive = $duplicateInSource.Move($archiveFolder)
    if ($null -eq $duplicateInArchive) { throw 'Could not move second test duplicate back into disposable archive.' }
    $secondDestinationId = [string]$duplicateInArchive.EntryID
    if ([string]::IsNullOrWhiteSpace($secondDestinationId) -or
        $secondDestinationId -ceq $movedId) {
        throw 'Second archive item lacks a distinct EntryID; duplicate not established.'
    }
    Write-Host ("Second destination copy staged: distinct EntryID={0}; size={1}" -f
        ($secondDestinationId -cne $movedId),[long]$duplicateInArchive.Size)
    Release-OPAComObject -Object $duplicateInArchive
    Release-OPAComObject -Object $duplicateInSource
    Release-OPAComObject -Object $duplicate
    Release-OPAComObject -Object $destinationMail

    $stage = 'Read-only Ambiguous'
    # Record independent read-only observations even if the expected status
    # is not reached, so a missing/mutated second item is diagnosable.
    $srcSnapshot = New-OPAReadOnlyMoveSnapshot -Folder $sourceFolder `
        -FolderPath ([string]$sourceFolder.FolderPath) `
        -StoreIdentity ([string]$sourceStore.StoreID) -Role Source
    $dstSnapshot = New-OPAReadOnlyMoveSnapshot -Folder $archiveFolder `
        -FolderPath ([string]$archiveFolder.FolderPath) `
        -StoreIdentity ([string]$archiveStore.StoreID) -Role Destination -ArchivePst $archivePst
    $intentRecord = (Read-OPAOperationJournal -Path $journalPath).Events[0]
    $matchedSource = @($srcSnapshot.Items | Where-Object {
        Test-OPAMoveFingerprint -Intent $intentRecord -Observed $_
    })
    $matchedDestination = @($dstSnapshot.Items | Where-Object {
        Test-OPAMoveFingerprint -Intent $intentRecord -Observed $_
    })
    $duplicateDiagnostics = [pscustomobject]@{
        SourceScanComplete=[bool]$srcSnapshot.ScanComplete
        DestinationScanComplete=[bool]$dstSnapshot.ScanComplete
        SourceScannedCount=[int]$srcSnapshot.ScannedCount
        DestinationScannedCount=[int]$dstSnapshot.ScannedCount
        SourceRows=@($srcSnapshot.Items).Count
        DestinationRows=@($dstSnapshot.Items).Count
        SourceFingerprintMatches=$matchedSource.Count
        DestinationFingerprintMatches=$matchedDestination.Count
        DistinctSecondDestinationEntryId=($secondDestinationId -cne $movedId)
        SourceErrors=@($srcSnapshot.Errors)
        DestinationErrors=@($dstSnapshot.Errors)
        DestinationSizeValues=@($dstSnapshot.Items | ForEach-Object { [long]$_.Size })
        DestinationMessageIdMatches=@($dstSnapshot.Items | ForEach-Object {
            [string]$_.InternetMessageId -ceq [string]$intentRecord.InternetMessageId
        })
        DestinationSubjectMatches=@($dstSnapshot.Items | ForEach-Object {
            [string]$_.Subject -ceq [string]$intentRecord.Subject
        })
        DestinationSenderMatches=@($dstSnapshot.Items | ForEach-Object {
            [string]$_.Sender -ieq [string]$intentRecord.Sender
        })
    }
    Write-Host ("Diagnostics: destination rows={0}; matching fingerprints={1}; scan complete={2}" -f
        $duplicateDiagnostics.DestinationRows,
        $duplicateDiagnostics.DestinationFingerprintMatches,
        $duplicateDiagnostics.DestinationScanComplete)
    $r = Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $journalPath) `
        -OperationId $operationId -SourceSnapshot $srcSnapshot -DestinationSnapshot $dstSnapshot
    Add-OPA263Outcome -Name 'Duplicate destination matches' `
        -ExpectedStatus Ambiguous -Result $r -Output $results

    $stage = 'Review journal unchanged'
    $state = Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $journalPath)
    if (-not $state.BlockAutomaticRetry -or $state.LastSequence -ne 1 -or
        @($state.Indeterminate).Count -ne 1) {
        throw 'FAIL: an uncompleted MailMove became automatically repeatable.'
    }
    Write-Host 'PASS Journal: one durable Intent; unresolved and retry blocked.'
}
catch {
    $failure = ("{0}: {1}" -f $stage,$_.Exception.Message)
    Write-Warning ("Integration halted safely at '{0}': {1}" -f $stage,$_.Exception.Message)
}
finally {
    $report = [ordered]@{
        Build='2.6.3-PREVIEW1'; RunId=$runId; TimestampUtc=[datetime]::UtcNow.ToString('o')
        SeedPst=$seedPath; SourcePst=$sourcePst; ArchivePst=$archivePst
        Journal=$journalPath; Stage=$stage; Failure=$failure
        DuplicateDiagnostics=$duplicateDiagnostics
        Scenarios=$results.ToArray()
        Note='Keep disposable PSTs and operation journal; do not auto-retry.'
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($reportPath,(ConvertTo-Json -InputObject $report -Depth 7),$utf8)
    Write-Host ("Report: {0}" -f $reportPath)
    Write-Host ("Journal: {0}" -f $journalPath)
    Write-Host 'Disposable PSTs remain mounted and are NOT deleted.'
}
if (-not [string]::IsNullOrWhiteSpace($failure)) { throw ("2.6.3 real Outlook integration FAILED: {0}" -f $failure) }
Write-Host 'PASS: 2.6.3 real Outlook COM reconciliation scenarios completed.'
