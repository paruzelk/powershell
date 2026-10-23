#requires -Version 5.1
# 2.6.3: independent, read-only recovery evidence for a pending MailMove.
# This file must NOT import MailMover or mutate PST/step/operation journals.
# No conclusion from this module authorizes an automatic second Move().

function New-OPAReadOnlyMoveSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][string]$FolderPath,
        [Parameter(Mandatory=$true)][string]$StoreIdentity,
        [ValidateSet('Source','Destination')][string]$Role = 'Source',
        [string]$ArchivePst = ''
    )

    # A folder's complete Items collection is observed; not GetItemFromID
    # alone, because an EntryID may change across PST/Outlook operations.
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $complete = $true
    $items = $null
    $initialCount = -1
    try {
        $actualPath = [string]$Folder.FolderPath
        if ([string]::IsNullOrWhiteSpace($actualPath) -or $actualPath -ine $FolderPath) {
            throw "Folder identity mismatch: expected '$FolderPath', got '$actualPath'."
        }
        $actualStore = [string]$Folder.StoreID
        if ([string]::IsNullOrWhiteSpace($actualStore) -or $actualStore -cne $StoreIdentity) {
            throw 'Folder store identity mismatch.'
        }
        $items = $Folder.Items
        if ($null -eq $items) { throw 'Folder Items collection is null.' }
        $initialCount = [int]$items.Count
        if ($initialCount -lt 0) { throw 'Invalid item count.' }
        for ($index=1; $index -le $initialCount; $index++) {
            $item = $null
            try {
                $item = $items.Item($index)
                if ($null -eq $item) { throw "Null item at index $index." }
                if ([int]$item.Class -ne 43) { continue } # Outlook MailItem
                $entry = [string]$item.EntryID
                $msgId = [string](Get-OPAInternetMessageId -Item $item)
                $subject = [string]$item.Subject
                $sender = [string]$item.SenderEmailAddress
                $size = [long]$item.Size
                if ([string]::IsNullOrWhiteSpace($entry)) { throw "MailItem without EntryID at $index." }
                # Absence of an identifier/field means that a potential match
                # cannot be ruled out. Never treat such a scan as complete.
                if ([string]::IsNullOrWhiteSpace($msgId) -or
                    [string]::IsNullOrWhiteSpace($subject) -or
                    [string]::IsNullOrWhiteSpace($sender) -or $size -le 0) {
                    throw "MailItem fingerprint incomplete at index $index."
                }
                [void]$rows.Add([pscustomobject]@{
                    EntryId=$entry; InternetMessageId=$msgId
                    Subject=$subject; Sender=$sender; Size=$size
                })
            }
            catch {
                $complete = $false
                [void]$errors.Add(("Item {0}: {1}" -f $index,$_.Exception.Message))
            }
            finally {
                if ($null -ne $item -and (Get-Command Release-OPAComObject -ErrorAction SilentlyContinue)) {
                    Release-OPAComObject -Object $item
                }
            }
        }
        $finalCount = [int]$items.Count
        if ($initialCount -ne $finalCount) {
            throw ("Folder item count changed during scan ({0} -> {1})." -f $initialCount,$finalCount)
        }
    }
    catch {
        $complete = $false
        [void]$errors.Add([string]$_.Exception.Message)
    }

    return [pscustomobject]@{
        Role=$Role; FolderPath=$FolderPath; StoreIdentity=$StoreIdentity
        ArchivePst=$ArchivePst; ScanComplete=$complete
        ScannedCount=$initialCount; Items=$rows.ToArray()
        Errors=$errors.ToArray()
    }
}

function Test-OPAMoveFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Intent,
        [Parameter(Mandatory=$true)][object]$Observed
    )
    # A four-field fingerprint is evidence of a candidate, not a unique
    # content ID or proof of a move. Duplicates can share all four fields.
    if ([string]::IsNullOrWhiteSpace([string]$Intent.InternetMessageId) -or
        [string]::IsNullOrWhiteSpace([string]$Intent.Sender) -or
        [string]::IsNullOrWhiteSpace([string]$Intent.Subject) -or
        [long]$Intent.Size -le 0) {
        return $false
    }
    return (
        [string]$Observed.InternetMessageId -ceq [string]$Intent.InternetMessageId -and
        [string]$Observed.Subject -ceq [string]$Intent.Subject -and
        [string]$Observed.Sender -ieq [string]$Intent.Sender -and
        [long]$Observed.Size -eq [long]$Intent.Size
    )
}

function Resolve-OPAInterruptedMoveEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Journal,
        [Parameter(Mandatory=$true)][string]$OperationId,
        [Parameter(Mandatory=$true)][object]$SourceSnapshot,
        [Parameter(Mandatory=$true)][object]$DestinationSnapshot
    )

    # Journal replay also validates monotonic sequence, consistent transaction
    # IDs and legal operation state transitions. Corruption throws (fail closed).
    $state = Resolve-OPAOperationRecovery -Journal $Journal
    $events = @($Journal.Events | Where-Object { [string]$_.OperationId -ceq $OperationId })
    if ($events.Count -eq 0) { throw "Unknown operation '$OperationId'." }
    $intentEvents = @($events | Where-Object { [string]$_.Phase -eq 'Intent' })
    if ($intentEvents.Count -ne 1) { throw 'Missing or duplicated MailMove Intent.' }
    $intent = $intentEvents[0]
    if ([string]$intent.OperationKind -cne 'MailMove') {
        throw 'Only a MailMove Intent can be evaluated for PST reconciliation.'
    }
    if ([string]$state.TransactionId -cne [string]$intent.TransactionId) {
        throw 'Journal transaction mismatch.'
    }
    $operationState = @(@($state.Resolved) + @($state.Indeterminate) |
        Where-Object { [string]$_.OperationId -ceq $OperationId })
    if ($operationState.Count -ne 1) { throw 'Operation state cannot be uniquely reconstructed.' }

    $status = 'InsufficientEvidence'
    $reason = 'Missing mandatory fingerprint or persisted destination/source identities.'
    $sourceCount = 0; $destinationCount = 0
    $destinationEntryId = ''

    $hasIntent = (
        -not [string]::IsNullOrWhiteSpace([string]$intent.SourceEntryId) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.SourceStoreId) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.SourceFolderPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.TargetFolderPath) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.ArchivePst) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.InternetMessageId) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.Subject) -and
        -not [string]::IsNullOrWhiteSpace([string]$intent.Sender) -and
        [long]$intent.Size -gt 0
    )

    if ([string]$operationState[0].Status -ne 'Indeterminate') {
        $status='AlreadyTerminal'
        $reason='Operation already has a terminal journal event; no recovery action permitted.'
    }
    elseif ([bool]$Journal.TrailingPartial) {
        $status='UntrustedJournal'
        $reason='Journal contains an unterminated record; do not act on incomplete evidence.'
    }
    elseif ($hasIntent) {
        # Refuse a snapshot with an intentionally missing inventory; a
        # missing Items property cannot establish zero candidates.
        if ($null -eq $SourceSnapshot.Items -or $null -eq $DestinationSnapshot.Items) {
            $status='IncompleteScan'
            $reason='Source or destination inventory was not provided.'
            return [pscustomobject]@{
                TransactionId=[string]$intent.TransactionId; OperationId=$OperationId
                Status=$status; Reason=$reason; SourceMatches=0; DestinationMatches=0
                DestinationEntryId=''; ProvenMoved=$false
                AutomaticRetryAllowed=$false; RequiresManualReview=$true
                JournalLastSequence=[long]$state.LastSequence
                JournalTrailingPartial=[bool]$Journal.TrailingPartial
                EvidenceKind='ReadOnlyFingerprintCandidate'
            }
        }
        $expectedArchive = ''
        $observedArchive = ''
        try {
            $expectedArchive = [IO.Path]::GetFullPath([string]$intent.ArchivePst)
            $observedArchive = [IO.Path]::GetFullPath([string]$DestinationSnapshot.ArchivePst)
        }
        catch { $expectedArchive = ''; $observedArchive = '' }
        $scopeCorrect = (
            [string]$SourceSnapshot.Role -ceq 'Source' -and
            [string]$DestinationSnapshot.Role -ceq 'Destination' -and
            [string]$SourceSnapshot.StoreIdentity -ceq [string]$intent.SourceStoreId -and
            [string]$SourceSnapshot.FolderPath -ieq [string]$intent.SourceFolderPath -and
            [string]$DestinationSnapshot.FolderPath -ieq [string]$intent.TargetFolderPath -and
            -not [string]::IsNullOrWhiteSpace($expectedArchive) -and
            $expectedArchive -ieq $observedArchive
        )
        if (-not $scopeCorrect) {
            $status='ScopeMismatch'
            $reason='Observed store/folder/PST identities differ from durable Intent.'
        }
        elseif (-not [bool]$SourceSnapshot.ScanComplete -or
                -not [bool]$DestinationSnapshot.ScanComplete) {
            $status='IncompleteScan'
            $reason='One or both folders could not be completely scanned.'
        }
        else {
            $sourceMatches = @($SourceSnapshot.Items | Where-Object {
                Test-OPAMoveFingerprint -Intent $intent -Observed $_
            })
            $destinationMatches = @($DestinationSnapshot.Items | Where-Object {
                Test-OPAMoveFingerprint -Intent $intent -Observed $_
            })
            $sourceCount = $sourceMatches.Count
            $destinationCount = $destinationMatches.Count
            $entryCollision = @($SourceSnapshot.Items | Where-Object {
                [string]$_.EntryId -ceq [string]$intent.SourceEntryId -and
                -not (Test-OPAMoveFingerprint -Intent $intent -Observed $_)
            }).Count -gt 0
            $blankIds = @($destinationMatches | Where-Object {
                [string]::IsNullOrWhiteSpace([string]$_.EntryId)
            }).Count -gt 0
            if ($entryCollision -or $blankIds) {
                $status='IdentityConflict'
                $reason='EntryId conflicts with fingerprint or destination identity is missing.'
            }
            elseif ($sourceCount -gt 1 -or $destinationCount -gt 1) {
                $status='Ambiguous'
                $reason='Multiple fingerprint matches; cannot establish unique identity.'
            }
            elseif ($sourceCount -eq 1 -and $destinationCount -eq 0) {
                $status='SourceOnly'
                $reason='Only source folder has a candidate; not proof of a safely repeatable Move.'
            }
            elseif ($sourceCount -eq 0 -and $destinationCount -eq 1) {
                $status='DestinationCandidate'
                $reason='Unique destination fingerprint, source folder empty; independent proof/manual approval still required.'
                $destinationEntryId = [string]$destinationMatches[0].EntryId
            }
            elseif ($sourceCount -eq 1 -and $destinationCount -eq 1) {
                $status='BothPresent'
                $reason='Matching mail exists on both sides: possible copied/duplicate message.'
            }
            else {
                $status='MissingBoth'
                $reason='No matching message in either recorded folder.'
            }
        }
    }

    # All outcomes are observations. Not even SourceOnly permits another
    # Move, and DestinationCandidate MUST NOT append a Reconciled event.
    return [pscustomobject]@{
        TransactionId=[string]$intent.TransactionId
        OperationId=$OperationId
        Status=$status; Reason=$reason
        SourceMatches=$sourceCount; DestinationMatches=$destinationCount
        DestinationEntryId=$destinationEntryId
        ProvenMoved=$false
        AutomaticRetryAllowed=$false
        RequiresManualReview=$true
        JournalLastSequence=[long]$state.LastSequence
        JournalTrailingPartial=[bool]$Journal.TrailingPartial
        EvidenceKind='ReadOnlyFingerprintCandidate'
    }
}

function Invoke-OPAReadOnlyInterruptedMoveReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JournalPath,
        [Parameter(Mandatory=$true)][string]$OperationId,
        [Parameter(Mandatory=$true)][object]$SourceFolder,
        [Parameter(Mandatory=$true)][object]$DestinationFolder,
        [Parameter(Mandatory=$true)][string]$SourceStoreId,
        [Parameter(Mandatory=$true)][string]$SourceFolderPath,
        [Parameter(Mandatory=$true)][string]$DestinationStoreId,
        [Parameter(Mandatory=$true)][string]$TargetFolderPath,
        [Parameter(Mandatory=$true)][string]$ArchivePst
    )
    # Caller MUST first independently resolve the exact POP3 source store and
    # the EXISTING mounted archive store; this API never mounts or creates PSTs.
    $j = Read-OPAOperationJournal -Path $JournalPath
    $src = New-OPAReadOnlyMoveSnapshot -Folder $SourceFolder -FolderPath $SourceFolderPath -StoreIdentity $SourceStoreId -Role Source
    $dst = New-OPAReadOnlyMoveSnapshot -Folder $DestinationFolder -FolderPath $TargetFolderPath -StoreIdentity $DestinationStoreId -Role Destination -ArchivePst $ArchivePst
    Resolve-OPAInterruptedMoveEvidence -Journal $j -OperationId $OperationId -SourceSnapshot $src -DestinationSnapshot $dst
}
