#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Runtime/ComManager.ps1')
    . (Join-Path $script:root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchivePlanner.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveVerifier.ps1')
    . (Join-Path $script:root 'Core/Archive/MailMover.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH6Orchestration.ps1')
    function New-ARCH6Folder {
        param([string]$Name,[string]$Path,[object[]]$Entries=@(),[object[]]$Children=@())
        $items=[pscustomobject]@{Count=$Entries.Count;Entries=$Entries}
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {param($i) $this.Entries[$i-1]}
        [pscustomobject]@{Name=$Name;EntryID=$Path;FolderPath=$Path;DefaultItemType=0;Items=$items;Folders=$Children}
    }
    function New-ARCH6Returned {
        param([int]$Limit,[int]$NotMoved=0)
        [pscustomobject]@{Status='BatchReturnedRestartAndResumeRequired';TransactionId='20261124-120000-01234567';Planned=$Limit;Returned=($Limit-$NotMoved);NotMoved=$NotMoved}
    }
    function New-ARCH6Verified {
        param([int]$Count,[int]$Skipped=0,[string]$Id='20261124-120000-01234567')
        [pscustomobject]@{Status='BatchVerifiedReconciledAndIndexed';TransactionId=$Id;Planned=($Count+$Skipped);Verified=$Count;Reconciled=$Count;Indexed=$Count;NotMoved=$Skipped;LogicalBytes=([long]$Count*100)}
    }
}
Describe 'ARCH6a empty folder and root verification scope' {
    It 'keeps empty nested mail folders out of default writer selection' {
        $empty=New-ARCH6Folder -Name Empty -Path '\\PST\Empty'
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Children @($empty)
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root).Count | Should -Be 0
    }
    It 'returns empty original folders on independent verification' {
        $empty=New-ARCH6Folder -Name Empty -Path '\\PST\Empty'
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Children @($empty)
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeEmptyFolders).FolderPath | Should -Be '\\PST\Empty'
    }
    It 'includes root only in explicit observation scope' {
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @([pscustomobject]@{EntryID='S1'})
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root).Count | Should -Be 0
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootForVerification).FolderPath | Should -Be '\\PST'
    }
    It 'still prunes excluded Outbox subtree even when empty folders included' {
        $child=New-ARCH6Folder -Name Child -Path '\\PST\Outbox\Child'
        $outbox=New-ARCH6Folder -Name Outbox -Path '\\PST\Outbox' -Children @($child)
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Children @($outbox)
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeEmptyFolders).Count | Should -Be 0
    }
    It 'recognizes a formerly nonempty source folder after it becomes empty' {
        $f=New-ARCH6Folder -Name Empty -Path '\\PST\Empty'
        $row=[pscustomobject]@{SourceEntryId='S1';ArchiveEntryId='A1';SourceFolderPath=$f.FolderPath;ArchivePst='C:\Archive.pst';TargetFolderPath='\\A\2020\Empty';SourceSemanticWitness=$null}
        $r=Test-OPAArchiveMoves -Namespace ([pscustomobject]@{}) -SourceFolder @($f) -ExpectedMoved 1 -ExpectedMoves @($row) -RequireSourceAbsentAcrossFolders -BoundedSourceIdMemory
        $r.MissingEntryIds | Should -Not -Contain 'SOURCE_FOLDER_UNKNOWN:\\PST\Empty'
        $r.MissingEntryIds | Should -Not -Contain 'STILL_IN_SOURCE:S1'
        $r.Verified | Should -BeFalse # destination deliberately not provided
    }
    It 'detects a claimed ID in a different observed source folder' {
        $f=New-ARCH6Folder -Name Empty -Path '\\PST\Empty'
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @([pscustomobject]@{EntryID='S1'})
        $row=[pscustomobject]@{SourceEntryId='S1';ArchiveEntryId='A1';SourceFolderPath=$f.FolderPath;ArchivePst='C:\Archive.pst';TargetFolderPath='\\A\2020\Empty';SourceSemanticWitness=$null}
        $r=Test-OPAArchiveMoves -Namespace ([pscustomobject]@{}) -SourceFolder @($f,$root) -ExpectedMoved 1 -ExpectedMoves @($row) -RequireSourceAbsentAcrossFolders -BoundedSourceIdMemory
        $r.MissingEntryIds | Should -Contain 'STILL_IN_SOURCE:S1'
    }
    It 'blocks verification when an observed item has no identity' {
        $f=New-ARCH6Folder -Name Empty -Path '\\PST\Empty' -Entries @([pscustomobject]@{EntryID=''})
        $r=Test-OPAArchiveMoves -Namespace ([pscustomobject]@{}) -SourceFolder @($f) -ExpectedMoved 0 -ExpectedMoves @() -BoundedSourceIdMemory
        $r.Verified | Should -BeFalse
        ($r.MissingEntryIds -join ';') | Should -Match 'SOURCE_FOLDER_UNREADABLE'
    }
}
Describe 'ARCH6b/d bounded automatic sequence' {
    BeforeEach {
        $script:limits=New-Object System.Collections.Generic.List[int]
        $script:restarts=0;$script:resumes=0;$script:count=0
        $script:record={param($phase,$data)}
        $script:archive={param($limit) [void]$script:limits.Add($limit);$script:count=$limit;New-ARCH6Returned -Limit $limit}
        $script:restart={param($id) $script:restarts++}
        $script:resume={param($id) $script:resumes++;New-ARCH6Verified -Count $script:count -Id $id}
    }
    It 'runs beyond 500 total but never exceeds bounded per-batch limit' {
        $r=Invoke-OPAARCH6Sequence -Archive $script:archive -Restart $script:restart -Resume $script:resume -Record $script:record -BatchSize 500 -MaxMessages 1201 -MaxBatches 10
        ($script:limits.ToArray() -join ',') | Should -BeExactly '500,500,201'
        $r.Verified | Should -Be 1201
        $r.Batches | Should -Be 3
        $script:restarts | Should -Be 3
        $r.Status | Should -BeExactly 'MessageLimitReached'
    }
    It 'honors maximum batch count' {
        $r=Invoke-OPAARCH6Sequence -Archive $script:archive -Restart $script:restart -Resume $script:resume -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 2
        $r.Verified | Should -Be 20
        $r.Status | Should -BeExactly 'BatchLimitReached'
    }
    It 'stops after a skipped message rather than retrying it' {
        $a={param($limit) [void]$script:limits.Add($limit);New-ARCH6Returned -Limit $limit -NotMoved 1}
        $r=Invoke-OPAARCH6Sequence -Archive $a -Restart $script:restart -Resume {param($id) New-ARCH6Verified -Count 9 -Skipped 1 -Id $id} -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10
        $r.Status | Should -BeExactly 'StoppedOnSkippedItems'
        $r.Verified | Should -Be 9
        $script:limits.Count | Should -Be 1
    }
    It 'does not restart a zero-Move completed batch' {
        $a={param($limit) [pscustomobject]@{Status='BatchCompletedNoMoves';TransactionId='20261124-120000-01234567';Planned=1;Verified=0;Indexed=0;RestartRequired=$false}}
        $r=Invoke-OPAARCH6Sequence -Archive $a -Restart $script:restart -Resume $script:resume -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10
        $r.Status | Should -BeExactly 'StoppedOnSkippedItems'
        $script:restarts | Should -Be 0
    }
    It 'stops without restart if no eligible folders exist' {
        $r=Invoke-OPAARCH6Sequence -Archive {param($limit) [pscustomobject]@{Status='NoEligibleFolders'}} -Restart $script:restart -Resume $script:resume -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10
        $r.Status | Should -BeExactly 'NoEligibleFolders'
        $script:restarts | Should -Be 0
    }
    It 'never starts a new batch after missing Archive receipt' {
        {Invoke-OPAARCH6Sequence -Archive {param($limit) [void]$script:limits.Add($limit)} -Restart $script:restart -Resume $script:resume -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10} | Should -Throw '*no unique result*'
        $script:limits.Count | Should -Be 1
        $script:restarts | Should -Be 0
    }
    It 'never starts a new batch after restart failure' {
        {Invoke-OPAARCH6Sequence -Archive $script:archive -Restart {param($id) throw 'shutdown timeout'} -Resume $script:resume -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10} | Should -Throw '*shutdown timeout*'
        $script:limits.Count | Should -Be 1
        $script:resumes | Should -Be 0
    }
    It 'requires same transaction identity after Resume' {
        {Invoke-OPAARCH6Sequence -Archive $script:archive -Restart $script:restart -Resume {param($id) New-ARCH6Verified -Count 10 -Id '20261124-120000-ffffffff'} -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10} | Should -Throw '*Resume not fully verified*'
        $script:limits.Count | Should -Be 1
    }
    It 'blocks a next batch if index count is incomplete' {
        {Invoke-OPAARCH6Sequence -Archive $script:archive -Restart $script:restart -Resume {param($id) $r=New-ARCH6Verified -Count 10 -Id $id;$r.Indexed=9;$r} -Record $script:record -BatchSize 10 -MaxMessages 100 -MaxBatches 10} | Should -Throw '*Resume not fully verified*'
        $script:limits.Count | Should -Be 1
    }
    It 'writes a durable UTF8 event log without appending any Move' {
        $path=Join-Path $TestDrive 'run.jsonl'
        Write-OPAARCH6RunEvent -Path $path -Phase RunStarted -Data ([pscustomobject]@{Limit=10})
        Write-OPAARCH6RunEvent -Path $path -Phase Stopped -Data ([pscustomobject]@{Message='test'})
        $rows=@(Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object {ConvertFrom-Json $_})
        $rows.Count | Should -Be 2
        $rows[1].Phase | Should -BeExactly 'Stopped'
    }
    It 'rejects foreign pending identity' {
        $src=Join-Path $TestDrive 'source.pst'
        $dir=Join-Path $TestDrive 'OutlookPOP3Archive-Transactions'
        [void][IO.Directory]::CreateDirectory($dir)
        $pending=Join-Path $dir 'ARCH4.pending'
        [IO.File]::WriteAllText($pending, (ConvertTo-Json ([pscustomobject]@{Schema='2.6.5-ARCH4.Pending.1';SourcePst=$src;Profile='Outlook';TransactionId='20261124-120000-01234567';MoveProcessId=123;MoveProcessStartUtcTicks=123})))
        {Get-OPAARCH6PendingRecord -SourcePst $src -ProfileName Outlook -TransactionId '20261124-120000-ffffffff'} | Should -Throw '*identity mismatch*'
    }
}
Describe 'ARCH6e explicit capacity and CLI' {
    It 'disables only application capacity via internal infinity sentinel' {
        Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB ([double]::PositiveInfinity) -SafetyMarginGB 0 | Should -Be ([int64]::MaxValue)
        Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes (90GB) -MaxArchivePstSizeGB ([double]::PositiveInfinity) -SafetyMarginGB 0 | Should -BeExactly 'WithinSafe'
    }
    It 'keeps finite capacity guard unchanged' {
        Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes (11GB) -MaxArchivePstSizeGB 10 -SafetyMarginGB 0.5 | Should -BeExactly 'HardLimitExceeded'
    }
    It 'main accepts explicit no cap in test WhatIf with no PST writes' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -Limit 10 -DisableArchivePstSizeLimit -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path $src | Should -BeFalse
    }
    It 'main rejects conflicting finite cap and no-cap switch' {
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'not-created.pst') -ConfirmTestArchive -Limit 10 -DisableArchivePstSizeLimit -MaxArchivePstSizeGB 20 -WhatIf} | Should -Throw
    }
    It 'controller WhatIf accepts total greater than 500 but writes nothing' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -ConfirmOutlookRestart -BatchSize 500 -MaxMessages 10000 -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path $src | Should -BeFalse
    }
    It 'controller refuses without restart consent before COM' {
        {& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'not-created.pst') -ConfirmTestArchive -WhatIf} | Should -Throw
    }
    It 'controller rejects recovery with new archive options' {
        {& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'not-created.pst') -ConfirmTestArchive -ConfirmOutlookRestart -RecoverTransaction '20261124-120000-01234567' -MaxMessages 100 -WhatIf} | Should -Throw
    }
}

Describe 'ARCH6f1 exact restart identity and ROT fallback' {
    It 'uses a registered active application without activation' {
        $r=Get-OPAARCH6RestartApplication -GetActive { [pscustomobject]@{Kind='active'} } -Activate { throw 'unexpected activation' }
        $r.Kind | Should -BeExactly 'active'
    }
    It 'activates once when ROT returns MK_E_UNAVAILABLE' {
        $r=Get-OPAARCH6RestartApplication -GetActive { throw [Runtime.InteropServices.COMException]::new('ROT unavailable',-2147221021) } -Activate { [pscustomobject]@{Kind='COM'} }
        $r.Kind | Should -BeExactly 'COM'
    }
    It 'does not activate for unrelated COM errors' {
        {Get-OPAARCH6RestartApplication -GetActive {throw [Runtime.InteropServices.COMException]::new('Access denied',-2147024891)} -Activate {throw 'unexpected activation'}} | Should -Throw '*Access denied*'
    }
    It 'accepts only the exact sealed Move process' {
        $start=[datetime]'2026-11-25T07:20:00Z'
        $p=[pscustomobject]@{MoveProcessId=123;MoveProcessStartUtcTicks=$start.ToUniversalTime().Ticks}
        {Assert-OPAARCH6RestartProcess -Pending $p -Processes @([pscustomobject]@{Id=123;StartTime=$start})} | Should -Not -Throw
    }
    It 'rejects a replacement process even when PID was reused' {
        $start=[datetime]'2026-11-25T07:20:00Z'
        $p=[pscustomobject]@{MoveProcessId=123;MoveProcessStartUtcTicks=$start.ToUniversalTime().Ticks}
        {Assert-OPAARCH6RestartProcess -Pending $p -Processes @([pscustomobject]@{Id=123;StartTime=$start.AddSeconds(1)})} | Should -Throw '*never Quit a replacement*'
    }
    It 'rejects zero or multiple processes before Quit' {
        $start=[datetime]'2026-11-25T07:20:00Z'
        $p=[pscustomobject]@{MoveProcessId=123;MoveProcessStartUtcTicks=$start.ToUniversalTime().Ticks}
        {Assert-OPAARCH6RestartProcess -Pending $p -Processes @()} | Should -Throw '*never Quit a replacement*'
        {Assert-OPAARCH6RestartProcess -Pending $p -Processes @([pscustomobject]@{Id=123;StartTime=$start},[pscustomobject]@{Id=456;StartTime=$start})} | Should -Throw '*never Quit a replacement*'
    }
}

Describe 'ARCH6f2 explicit root mail selection and reserved route' {
    BeforeAll {
        . (Join-Path $script:root 'Core/Archive/ArchiveGrouping.ps1')
        . (Join-Path $script:root 'Core/Archive/ArchiveSelector.ps1')
        . (Join-Path $script:root 'Core/Archive/ARCH4Batch.ps1')
    }
    It 'includes root only with explicit write selection while preserving normal folders' {
        $mail=[pscustomobject]@{EntryID='R1'}
        $child=New-ARCH6Folder -Name Inbox -Path '\\PST\Inbox' -Entries @($mail)
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @($mail) -Children @($child)
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root).FolderPath | Should -Be '\\PST\Inbox'
        $f=@(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootMail)
        $f.Count | Should -Be 2
        $f.FolderPath | Should -Contain '\\PST'
    }
    It 'exact root filter does not select nested folders' {
        $mail=[pscustomobject]@{EntryID='R1'}
        $child=New-ARCH6Folder -Name Inbox -Path '\\PST\Inbox' -Entries @($mail)
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @($mail) -Children @($child)
        $f=@(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootMail)
        @(Select-OPAARCH5SourceFolders -EligibleFolders $f -IncludeFolderPath '\\PST').FolderPath | Should -Be '\\PST'
    }
    It 'refuses exact root selection without explicit inclusion' {
        $child=New-ARCH6Folder -Name Inbox -Path '\\PST\Inbox' -Entries @([pscustomobject]@{EntryID='I1'})
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @([pscustomobject]@{EntryID='R1'}) -Children @($child)
        $f=@(Get-OPAEligiblePop3MailFolders -RootFolder $root)
        {Select-OPAARCH5SourceFolders -EligibleFolders $f -IncludeFolderPath '\\PST'} | Should -Throw '*not uniquely eligible*'
    }
    It 'includes emptied root for verification and exact root selection' {
        $root=New-ARCH6Folder -Name PST -Path '\\PST'
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootMail).Count | Should -Be 0
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootMail -IncludeEmptyFolders).Count | Should -Be 1
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootForVerification).Count | Should -Be 1
    }
    It 'excludes Outbox children even when root enabled' {
        $child=New-ARCH6Folder -Name Outbox -Path '\\PST\Outbox' -Entries @([pscustomobject]@{EntryID='O1'})
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries @([pscustomobject]@{EntryID='R1'}) -Children @($child)
        @(Get-OPAEligiblePop3MailFolders -RootFolder $root -IncludeRootMail).FolderPath | Should -Be '\\PST'
    }
    It 'routes root mail to reserved folder under all four grouping modes' {
        $date=[datetime]'2020-04-01'
        Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST' -Grouping None | Should -BeExactly '__OPA_ROOT_MAIL__'
        Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST' -Grouping Year | Should -BeExactly '2020\__OPA_ROOT_MAIL__'
        Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST' -Grouping YearQuarter | Should -BeExactly '2020\Q2\__OPA_ROOT_MAIL__'
        Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST' -Grouping YearMonth | Should -BeExactly '2020\04\__OPA_ROOT_MAIL__'
    }
    It 'preserves normal nested route and rejects reserved user-folder collisions' {
        $date=[datetime]'2020-04-01'
        Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST\Parent\Child' -Grouping YearQuarter | Should -BeExactly '2020\Q2\Parent\Child'
        {Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderPath '\\PST\__opa_root_mail__\Child' -Grouping YearQuarter} | Should -Throw '*reserved root mail route*'
    }
    It 'validates the sealed root destination and rejects wrong destination or year' {
        $opts=@{SourcePst='C:\Test\source.pst';ArchiveDate=[datetime]'2020-04-01';SourceFolderPath='\\PST';Grouping='YearQuarter'}
        {Assert-OPAARCH5Route @opts -TargetFolderPath '\\Archive\2020\Q2\__OPA_ROOT_MAIL__' -ArchivePst 'C:\Test\source.Archive-2020-02.pst'} | Should -Not -Throw
        {Assert-OPAARCH5Route @opts -TargetFolderPath '\\Archive\2020\Q2\Inbox' -ArchivePst 'C:\Test\source.Archive-2020.pst'} | Should -Throw '*ArchiveRouteMismatch*'
        {Assert-OPAARCH5Route @opts -TargetFolderPath '\\Archive\2020\Q2\__OPA_ROOT_MAIL__' -ArchivePst 'C:\Test\source.Archive-2021.pst'} | Should -Throw '*ArchiveRouteMismatch*'
    }
    It 'selects only eligible MailItem class, date and nonduplicate root IDs' {
        $old=[datetime]'2020-01-01';$young=[datetime]'2025-01-01'
        $entries=@(
            [pscustomobject]@{Class=43;EntryID='R1';Subject='Mail';ReceivedTime=$old;SentOn=$old;SenderEmailAddress='';Size=100},
            [pscustomobject]@{Class=43;EntryID='R2';Subject='Duplicate';ReceivedTime=$old;SentOn=$old;SenderEmailAddress='';Size=100},
            [pscustomobject]@{Class=26;EntryID='R3'},
            [pscustomobject]@{Class=43;EntryID='R4';Subject='Young';ReceivedTime=$young;SentOn=$young;SenderEmailAddress='';Size=100}
        )
        $root=New-ARCH6Folder -Name PST -Path '\\PST' -Entries $entries
        $result=@(Get-OPAArchiveCandidates -SourceFolder $root -Limit 10 -OlderThanCutoff ([datetime]'2021-01-01') -ExcludeEntryIds @('R2'))
        $result.Count | Should -Be 1
        $result[0].EntryID | Should -BeExactly 'R1'
        $result[0].SourceFolderPath | Should -BeExactly '\\PST'
    }
    It 'main accepts explicit root only for controlled Archive WhatIf' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -Limit 10 -IncludeRootMail -IncludeFolderPath '\\PST' -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path $src | Should -BeFalse
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Resume -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -IncludeRootMail -WhatIf} | Should -Throw
    }
    It 'controller accepts root opt-in in WhatIf and refuses it for recovery' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -ConfirmOutlookRestart -IncludeRootMail -IncludeFolderPath '\\PST' -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        {& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -ProfileName Outlook -SourcePst $src -ConfirmTestArchive -ConfirmOutlookRestart -IncludeRootMail -RecoverTransaction '20261125-102130-ef2c9ada' -WhatIf} | Should -Throw
    }
}
