#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2aMoveOutcomeFence.ps1')
    $script:mover=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
    $script:main=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
    $script:policy=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Archive/ARCH2aMoveOutcomeFence.ps1') -Raw -Encoding UTF8
    function New-ARCH2aStep {
        param([string]$Step='Move Started',[string]$EntryId='S1')
        return [pscustomobject]@{Step=$Step;EntryId=$EntryId}
    }
    function New-ARCH2aPlan {
        return @([pscustomobject]@{EntryId='S1'},[pscustomobject]@{EntryId='S2'})
    }
    function New-ARCH2aTransaction {
        return [pscustomobject]@{
            State=[pscustomobject]@{PlannedItems=(New-ARCH2aPlan)}
        }
    }
}
Describe 'ARCH2a durable original Move claim fence' {
    It 'returns documented classifier schema' {
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems (New-ARCH2aPlan)).Schema |
            Should -BeExactly '2.6.5-ARCH2a.MoveClaimFence.1'
    }
    It 'permits only policy classification, not a production writer' {
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems (New-ARCH2aPlan)
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'recognizes a pristine journal as no unresolved attempt observed' {
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems (New-ARCH2aPlan)
        $r.SafeToContinueFromThisJournal | Should -BeTrue
    }
    It 'does not treat a pristine journal as independent content proof' {
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems (New-ARCH2aPlan)).IndependentContentVerificationPerformed |
            Should -BeFalse
    }
    It 'flags Started with no Completed as unresolved' {
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @((New-ARCH2aStep)) -PlannedItems (New-ARCH2aPlan)
        $r.SafeToContinueFromThisJournal | Should -BeFalse
        $r.UnresolvedSourceIds | Should -Contain 'S1'
    }
    It 'does not consider ordinary Skipped after Started as retry approval' {
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @((New-ARCH2aStep),(New-ARCH2aStep -Step 'Skipped')) -PlannedItems (New-ARCH2aPlan)
        $r.UnresolvedSourceIds | Should -Contain 'S1'
    }
    It 'does not consider MoveFailed logged text completion' {
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @((New-ARCH2aStep),(New-ARCH2aStep -Step 'MoveFailed')) -PlannedItems (New-ARCH2aPlan)
        $r.SafeToContinueFromThisJournal | Should -BeFalse
    }
    It 'rejects Move Indeterminate even if earlier Completed is present' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'),(New-ARCH2aStep -Step 'Move Indeterminate'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeFalse
    }
    It 'recognizes one Started and one Completed as no unresolved claim' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeTrue
    }
    It 'recognizes legacy Move n/n completion marker' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move 1/2'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeTrue
    }
    It 'recognizes one manually reconciled destination marker' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Reconciled'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeTrue
    }
    It 'does not claim Reconciled means full semantic verification' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Reconciled'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).IndependentContentVerificationPerformed |
            Should -BeFalse
    }
    It 'blocks two Started attempts for same source even if a Completed appears' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'),(New-ARCH2aStep))
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)
        $r.SafeToContinueFromThisJournal | Should -BeFalse
        $r.IssueCodes | Should -Contain 'MultipleAttemptsForSameSourceId'
    }
    It 'counts attempts using case-insensitive EntryId identity' {
        $steps=@((New-ARCH2aStep -EntryId 's1'),(New-ARCH2aStep -EntryId 'S1'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).IssueCodes |
            Should -Contain 'MultipleAttemptsForSameSourceId'
    }
    It 'rejects a journaled Move Started with missing EntryId' {
        $steps=@((New-ARCH2aStep -EntryId ''))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).IssueCodes |
            Should -Contain 'MoveStepMissingOrUnknownPlannedId'
    }
    It 'rejects Move Started for unplanned source' {
        $steps=@((New-ARCH2aStep -EntryId 'OTHER'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeFalse
    }
    It 'rejects orphan Move Completed for unknown source' {
        $steps=@((New-ARCH2aStep -EntryId 'OTHER' -Step 'Move Completed'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).IssueCodes |
            Should -Contain 'MoveStepMissingOrUnknownPlannedId'
    }
    It 'does not treat an unrelated harmless step as a Move claim' {
        $steps=@((New-ARCH2aStep -Step 'Plan'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).SafeToContinueFromThisJournal |
            Should -BeTrue
    }
    It 'supports two independently completed planned messages' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'),(New-ARCH2aStep -EntryId 'S2'),(New-ARCH2aStep -Step 'Move Completed' -EntryId 'S2'))
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)
        $r.AttemptedSourceCount | Should -Be 2
        $r.SafeToContinueFromThisJournal | Should -BeTrue
    }
    It 'flags exactly one incomplete attempt in two-message batch' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'),(New-ARCH2aStep -EntryId 'S2'))
        $r=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)
        $r.UnresolvedSourceIds | Should -Contain 'S2'
        $r.UnresolvedSourceIds | Should -Not -Contain 'S1'
    }
    It 'preserves original claims as immutable' {
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems (New-ARCH2aPlan)).HistoricalMoveClaimsRewritten |
            Should -BeFalse
    }
    It 'never permits automatic retry on success classification' {
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'))
        (Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $steps -PlannedItems (New-ARCH2aPlan)).AutomaticMoveRetryAllowed |
            Should -BeFalse
    }
    It 'rejects duplicate source EntryIds in the original plan' {
        $planned=@([pscustomobject]@{EntryId='S1'},[pscustomobject]@{EntryId='s1'})
        {Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems $planned} | Should -Throw
    }
    It 'rejects empty original planned EntryId' {
        $planned=@([pscustomobject]@{EntryId=''})
        {Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems $planned} | Should -Throw
    }
    It 'rejects null original planned entry' {
        $planned=@($null)
        {Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @() -PlannedItems $planned} | Should -Throw
    }
    It 'rejects null journal record' {
        {Test-OPA265ARCH2aUnresolvedMoveSteps -Steps @($null) -PlannedItems (New-ARCH2aPlan)} | Should -Throw
    }
    It 'fails to assert no unresolved Move when Started lacks Completed' {
        $tx=New-ARCH2aTransaction
        {Assert-OPA265ARCH2aNoUnresolvedMove -Transaction $tx -JournalSteps @((New-ARCH2aStep))} | Should -Throw
    }
    It 'allows classification of fully completed original journal without writer permit' {
        $tx=New-ARCH2aTransaction
        $steps=@((New-ARCH2aStep),(New-ARCH2aStep -Step 'Move Completed'))
        (Assert-OPA265ARCH2aNoUnresolvedMove -Transaction $tx -JournalSteps $steps).WriterPermit | Should -BeFalse
    }
    It 'rejects missing transaction state' {
        {Assert-OPA265ARCH2aNoUnresolvedMove -Transaction ([pscustomobject]@{State=$null}) -JournalSteps @()} |
            Should -Throw
    }
    It 'rejects missing original planned items in transaction' {
        {Assert-OPA265ARCH2aNoUnresolvedMove -Transaction ([pscustomobject]@{State=[pscustomobject]@{PlannedItems=$null}}) -JournalSteps @()} |
            Should -Throw
    }
}
Describe 'ARCH2a DEV writer closure and real legacy Move sequence guards' {
    It 'blocks mutating Archive in DEV' {
        {Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Archive} | Should -Throw
    }
    It 'blocks mutating Resume in DEV' {
        {Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Resume} | Should -Throw
    }
    It 'blocks mutating Auto in DEV' {
        {Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Auto} | Should -Throw
    }
    It 'permits read-only Analyze' {
        (Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Analyze).Status | Should -BeExactly 'ReadOnlyModePermitted'
    }
    It 'permits read-only Plan' {
        (Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Plan).Status | Should -BeExactly 'ReadOnlyModePermitted'
    }
    It 'never grants production writer for Analyze' {
        (Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode Analyze).WriterPermit | Should -BeFalse
    }
    It 'rejects arbitrary invalid Mode value' {
        {Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode DeleteEverything} | Should -Throw
    }
    It 'entrypoint invokes writer closure before Outlook discovery' {
        $guard=$script:main.IndexOf('Assert-OPA265ARCH2aDevelopmentWriterClosed')
        $discovery=$script:main.IndexOf('Core\Version.ps1')
        $guard | Should -BeGreaterThan 0
        $discovery | Should -BeGreaterThan $guard
    }
    It 'entrypoint imports source-only safety policy' {
        $script:main | Should -Match 'ARCH2aMoveOutcomeFence.ps1'
    }
    It 'main mover writes Move Started with checkpoint before COM Move' {
        $claim=$script:mover.IndexOf("-Step 'Move Started'")
        $call=$script:mover.IndexOf('$item.Move($dest.Folder)')
        $claim | Should -BeGreaterThan 0
        $call | Should -BeGreaterThan $claim
        $script:mover | Should -Match "Move Started'.*-WriteCheckpoint"
    }
    It 'main mover force-flushes claim before COM Move' {
        $claim=$script:mover.IndexOf("-Step 'Move Started'")
        $call=$script:mover.IndexOf('$item.Move($dest.Folder)')
        $flushed=$script:mover.IndexOf('Sync-OPAStepJournalStreams',$claim)
        $flushed | Should -BeGreaterThan $claim
        $flushed | Should -BeLessThan $call
    }
    It 'main mover no longer marks Move exception as ordinary MoveFailed skipped' {
        $script:mover | Should -Not -Match "Reason='MoveFailed'"
        $script:mover | Should -Match "Step 'Move Indeterminate'"
    }
    It 'main mover throws on unknown Outlook Move outcome' {
        $script:mover | Should -Match 'MOVE OUTCOME UNKNOWN'
        $script:mover | Should -Match 'no automatic retry'
    }
    It 'outer catch stops if Move attempt was claimed even when provider call threw' {
        $script:mover | Should -Match 'if \(\$moveCompleted -or \$moveAttemptClaimed\)'
    }
    It 'Resume loads full original journal rather than 200-entry in-memory tail' {
        $script:mover | Should -Match 'Read-OPAStepJournal -Transaction \$Transaction'
        $script:mover | Should -Match 'Assert-OPA265ARCH2aNoUnresolvedMove'
    }
    It 'Resume fails closed when original journal is missing' {
        $script:mover | Should -Match 'original step journal missing'
    }
    It 'Resume rejects unterminated potentially truncated journal tail' {
        $script:mover | Should -Match 'unterminated step journal'
        $script:mover | Should -Match '\$fs.ReadByte\(\) -ne 10'
    }
    It 'no new custom MAPI Size or flags waiver' {
        $script:policy | Should -Not -Match '0x0E070003|0x0E080003'
    }
    It 'safety policy has no Outlook COM reader or writer' {
        $script:policy | Should -Not -Match 'GetActiveObject|GetNamespace|New-Object -ComObject'
        $script:policy | Should -Not -Match '\.(Move|Copy|Save|Delete|Send|AddStore)\s*\('
    }
}
