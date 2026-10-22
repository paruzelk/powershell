# FIX10 regression checks: executable helper tests and safety guards.
BeforeAll {
    . "$PSScriptRoot/../../Core/Version.ps1"
    . "$PSScriptRoot/../../Core/Runtime/JsonSupport.ps1"
    . "$PSScriptRoot/../../Core/Runtime/ComManager.ps1"
    . "$PSScriptRoot/../../Core/Archive/SystemFolders.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveSelector.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveTransaction.ps1"
    . "$PSScriptRoot/../../Core/Archive/AutoRecoveryPolicy.ps1"
}

Describe 'FIX10 system folder policy' {
    It 'always excludes system Outbox even with opt-in for other folders' {
        $map = @{'SYSTEM_OUTBOX'='Outbox'; 'SYSTEM_JUNK'='Junk'}
        Test-OPAExcludedSystemFolder -Name 'Renamed' -EntryID 'SYSTEM_OUTBOX' -WellKnownEntryIdMap $map -ArchiveDeletedItems $true -ArchiveDrafts $true -ArchiveJunk $true | Should -BeTrue
        Test-OPAExcludedSystemFolder -Name 'Outbox' -EntryID 'UNMAPPED' -WellKnownEntryIdMap $map -ArchiveJunk $true | Should -BeTrue
        Test-OPASentLikeFolder -Name 'Outbox' -EntryID 'SYSTEM_OUTBOX' -WellKnownEntryIdMap $map | Should -BeFalse
    }
    It 'excludes junk by default and permits explicit opt-in' {
        $map = @{'SYSTEM_JUNK'='Junk'}
        Test-OPAExcludedSystemFolder -Name 'Renamed' -EntryID 'SYSTEM_JUNK' -WellKnownEntryIdMap $map | Should -BeTrue
        Test-OPAExcludedSystemFolder -Name 'Renamed' -EntryID 'SYSTEM_JUNK' -WellKnownEntryIdMap $map -ArchiveJunk $true | Should -BeFalse
        Test-OPAExcludedSystemFolder -Name 'Спам' -EntryID 'OTHER' -WellKnownEntryIdMap $map | Should -BeTrue
    }
    It 'preserves Deleted/Drafts policy and custom folders' {
        $map = @{'DELETED'='DeletedItems';'DRAFT'='Drafts';'SENT'='SentMail'}
        Test-OPAExcludedSystemFolder -Name 'Custom' -EntryID 'DELETED' -WellKnownEntryIdMap $map | Should -BeTrue
        Test-OPAExcludedSystemFolder -Name 'Custom' -EntryID 'DRAFT' -WellKnownEntryIdMap $map | Should -BeTrue
        Test-OPAExcludedSystemFolder -Name 'Custom' -EntryID 'DRAFT' -WellKnownEntryIdMap $map -ArchiveDrafts $true | Should -BeFalse
        Test-OPAExcludedSystemFolder -Name 'Drafts' -EntryID 'USER-DRAFTS' -WellKnownEntryIdMap $map | Should -BeFalse
        Test-OPASentLikeFolder -Name 'Renamed' -EntryID 'SENT' -WellKnownEntryIdMap $map | Should -BeTrue
    }
}

Describe 'FIX10 Restrict syntax and age-free selection' {
    It 'quotes the DASL property URI separately from the date comparison' {
        $filter = Get-OPADateRestrictFilter -Cutoff ([datetime]'2024-04-05T06:07:00')
        $filter | Should -Be ('@SQL="urn:schemas:httpmail:datereceived" < ' + [char]39 + '2024-04-05 06:07' + [char]39)
        $sent = Get-OPADateRestrictFilter -Cutoff ([datetime]'2024-04-05T06:07:00') -PreferSentOn
        $sent | Should -Match '^@SQL="http://schemas.microsoft.com/mapi/proptag/0x00390040" < '
    }
    It 'selects oldest messages even when Outlook Sort fails and there is no age cutoff' {
        $rows = @(
            [pscustomobject]@{Class=43;EntryID='new';ReceivedTime=[datetime]'2025-01-01';SentOn=[datetime]'2025-01-01';CreationTime=[datetime]'2025-01-01';Subject='N';SenderEmailAddress='s';Size=10},
            [pscustomobject]@{Class=43;EntryID='old';ReceivedTime=[datetime]'2019-01-01';SentOn=[datetime]'2019-01-01';CreationTime=[datetime]'2019-01-01';Subject='O';SenderEmailAddress='s';Size=10},
            [pscustomobject]@{Class=43;EntryID='mid';ReceivedTime=[datetime]'2022-01-01';SentOn=[datetime]'2022-01-01';CreationTime=[datetime]'2022-01-01';Subject='M';SenderEmailAddress='s';Size=10}
        )
        $items = [pscustomobject]@{Count=3;Rows=$rows}
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {param([int]$I) $this.Rows[$I-1]}
        $items | Add-Member -MemberType ScriptMethod -Name Sort -Value {param($Field,$Descending) throw 'Sort disabled in mock'}
        $folder = [pscustomobject]@{Name='Inbox'; EntryID='INBOX'; FolderPath='\\Source\Inbox';Items=$items}
        $selected = @(Get-OPAArchiveCandidates -SourceFolder $folder -Limit 1)
        $selected.Count | Should -Be 1
        $selected[0].EntryID | Should -Be 'old'
    }
}

Describe 'FIX10 Auto retry quarantine' {
    It 'increments retry counter across reads and refuses a fourth automatic attempt' {
        $checkpoint = Join-Path $TestDrive 'txA.json'
        Get-OPAAutoRetryCount -CheckpointPath $checkpoint | Should -Be 0
        Register-OPAAutoResumeAttempt -CheckpointPath $checkpoint -MaxAttempts 3 | Should -Be 1
        Register-OPAAutoResumeAttempt -CheckpointPath $checkpoint -MaxAttempts 3 | Should -Be 2
        Register-OPAAutoResumeAttempt -CheckpointPath $checkpoint -MaxAttempts 3 | Should -Be 3
        { Register-OPAAutoResumeAttempt -CheckpointPath $checkpoint -MaxAttempts 3 } | Should -Throw '*quarantined*'
        Get-OPAAutoRetryCount -CheckpointPath $checkpoint | Should -Be 3
        Clear-OPAAutoResumeAttempts -CheckpointPath $checkpoint
        Get-OPAAutoRetryCount -CheckpointPath $checkpoint | Should -Be 0
    }
    It 'refuses an unreadable retry marker instead of resetting the counter' {
        $checkpoint = Join-Path $TestDrive 'txB.json'
        Set-Content -LiteralPath (Get-OPAAutoRetryPath -CheckpointPath $checkpoint) -Value 'not-json' -Encoding UTF8
        { Get-OPAAutoRetryCount -CheckpointPath $checkpoint } | Should -Throw '*unreadable*'
    }
}

Describe 'FIX10 transaction and capacity safety guards' {
    It 'persists explicit folder policies in new transaction state' {
        $source = Join-Path $TestDrive 'sample.pst'
        $tx = New-OPAArchiveTransaction -SourcePst $source -ArchivePst '' -Limit 5 -OlderThanMonths 12 -ArchiveCutoff (Get-Date).AddMonths(-12) -ArchiveDeletedItems $true -ArchiveDrafts $true -ArchiveJunk $true
        $loaded = Get-OPAArchiveTransaction -SourcePst $source -TransactionId $tx.TransactionId
        $loaded.State.ArchiveDeletedItems | Should -BeTrue
        $loaded.State.ArchiveDrafts | Should -BeTrue
        $loaded.State.ArchiveJunk | Should -BeTrue
    }
    It 'continues after safe rollover but stops after a hard-limit breach' {
        $text = Get-Content -LiteralPath "$PSScriptRoot/../../Core/Archive/MailMover.ps1" -Raw
        # FIX12 separates safe-margin rollover from a hard-limit breach.
        $text | Should -Match '(?s)if \(\$postMoveCapacityAction -eq ''RolloverNext''\)\s*\{.*?-Step ''Capacity Rollover Required''.*?\bcontinue\s*\}'
        $text | Should -Match '(?s)if \(\$postMoveCapacityAction -eq ''HardLimitExceeded''\)\s*\{.*?-Status ''VerificationFailed''.*?\bthrow'
    }
    It 'requires explicit IgnoreAge when OlderThanMonths is zero in automatic or mutating modes' {
        $text = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.ps1" -Raw
        $text | Should -Match 'OlderThanMonths -eq 0 -and -not \$IgnoreAge'
    }
}
