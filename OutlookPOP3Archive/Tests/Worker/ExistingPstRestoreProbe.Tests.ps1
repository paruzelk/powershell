#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/ExistingPstRestoreGuard.ps1')
}
Describe '2.6.4-LIVE2 restore scope offline' {
    BeforeEach {
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $a=Join-Path $dir 'Active'
        $b=Join-Path $dir 'Backup'
        [void][IO.Directory]::CreateDirectory($a)
        [void][IO.Directory]::CreateDirectory($b)
        $src=Join-Path $a 'current.pst'
        $bak=Join-Path $b 'backup.pst'
        $data=New-Object byte[] 4096
        [IO.File]::WriteAllBytes($src,$data)
        [IO.File]::WriteAllBytes($bak,$data)
        $digest=(Get-FileHash -LiteralPath $bak -Algorithm SHA256).Hash
        $params=@{
            RunId=[guid]::NewGuid().ToString('D')
            SourcePst=$src
            BackupPst=$bak
            ExpectedBackupSHA256=$digest
            ExpectedSizeBytes=[long]4096
        }
    }
    It 'computes one-shot TEMP clone without authorizing MailMove' {
        $p=Get-OPA264RestorePlan @params
        $p.ClonePst | Should -Match 'RestoreCopy.pst$'
        $p.MailMoveAllowed | Should -BeFalse
    }
    It 'validates reference backup hash' {
        $params.ExpectedBackupSHA256=('f'*64)
        { Get-OPA264RestorePlan @params } | Should -Throw '*SHA-256*'
    }
    It 'rejects changed source PST size' {
        [IO.File]::AppendAllText($src,'changed')
        { Get-OPA264RestorePlan @params } | Should -Throw '*length*'
    }
    It 'rejects invalid RunId' {
        $params.RunId='invalid'
        { Get-OPA264RestorePlan @params } | Should -Throw '*GUID*'
    }
    It 'refuses clone scope reuse' {
        $p=Get-OPA264RestorePlan @params
        [void][IO.Directory]::CreateDirectory($p.Directory)
        try { { Assert-OPA264RestoreClonePlan -Plan $p } | Should -Throw '*artifacts*' }
        finally { [IO.Directory]::Delete($p.Directory,$true) }
    }
    It 'rejects unauthorized mutation flags' {
        $p=Get-OPA264RestorePlan @params
        $p.ExistingPstMutationAllowed=$true
        { Assert-OPA264RestoreClonePlan -Plan $p } | Should -Throw '*approved*'
    }
    It 'rejects a false scope marker' {
        $p=Get-OPA264RestorePlan @params
        { Assert-OPA264RestoreMarker -Plan $p -Marker ([pscustomobject]@{Purpose='Wrong'}) } | Should -Throw '*mismatches*'
    }
    It 'compares matching folder counts' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=7;Subfolders=0})}
        $r=Compare-OPA264RestoreFolderInventories -Source $a -Restored $a
        $r.FolderStructureAndCountsEqual | Should -BeTrue
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects restore count mismatch' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=7;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=6;Subfolders=0})}
        (Compare-OPA264RestoreFolderInventories -Source $a -Restored $b).FolderStructureAndCountsEqual | Should -BeFalse
    }
    It 'rejects duplicate restored folder names' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=7;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=2;Folders=@($a.Folders[0],$a.Folders[0])}
        { Compare-OPA264RestoreFolderInventories -Source $a -Restored $b } | Should -Throw '*duplicate*'
    }
    It 'rejects backup beside source' {
        $backupInSameDir=Join-Path (Split-Path $src) 'backup.pst'
        [IO.File]::Copy($src,$backupInSameDir)
        $params.BackupPst=$backupInSameDir
        { Get-OPA264RestorePlan @params } | Should -Throw '*data directory*'
    }
    It 'does not attach Outlook or move mail from pure scope helpers' {
        $file=Join-Path $PSScriptRoot '../../Core/Worker/ExistingPstRestoreGuard.ps1'
        $raw=Get-Content -LiteralPath $file -Raw
        $raw | Should -Not -Match '\.AddStoreEx\('
        $raw | Should -Not -Match '\$mail\.Move\('
    }
    It 'reports the exact relative folder with differing item counts' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Входящие';Items=26310;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Входящие';Items=26309;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.Schema | Should -Be '2.6.4-LIVE2B.Comparison.1'
        $result.DifferenceCount | Should -Be 1
        $result.DifferenceTypes[0] | Should -Be 'CountMismatch'
        $result.Differences[0].RelativePath | Should -Be 'Входящие'
        $result.Differences[0].Type | Should -Be 'ItemCountMismatch'
        $result.Differences[0].SourceItems | Should -Be 26310
        $result.Differences[0].RestoredItems | Should -Be 26309
    }
    It 'separately reports identical structure and differing item counts' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=21;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=22;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.FolderStructureEqual | Should -BeTrue
        $result.SubfolderCountsEqual | Should -BeTrue
        $result.ItemCountsEqual | Should -BeFalse
        $result.FolderStructureAndCountsEqual | Should -BeFalse
        $result.TotalItemsSource | Should -Be 21
        $result.TotalItemsRestored | Should -Be 22
    }
    It 'reports a subfolder count mismatch even when item count agrees' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='';Items=0;Subfolders=1})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='';Items=0;Subfolders=2})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.DifferenceCount | Should -Be 1
        $result.Differences[0].Type | Should -Be 'SubfolderCountMismatch'
        $result.ItemCountsEqual | Should -BeTrue
        $result.SubfolderCountsEqual | Should -BeFalse
    }
    It 'reports both item and subfolder mismatch in one folder record' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='';Items=2;Subfolders=1})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='';Items=1;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.Differences[0].Type | Should -Be 'ItemAndSubfolderCountMismatch'
        $result.DifferenceCount | Should -Be 1
    }
    It 'reports unexpected folder with null missing-source numeric fields' {
        $a=[pscustomobject]@{FolderCount=0;Folders=@()}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='New';Items=4;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.Differences[0].Type | Should -Be 'UnexpectedFolder'
        $result.Differences[0].RestoredItems | Should -Be 4
        $result.Differences[0].SourceItems | Should -BeNullOrEmpty
        $result.FolderStructureEqual | Should -BeFalse
    }
    It 'reports missing folder with null missing-restored numeric fields' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Old';Items=3;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=0;Folders=@()}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $result.Differences[0].Type | Should -Be 'MissingFolder'
        $result.Differences[0].SourceItems | Should -Be 3
        $result.Differences[0].RestoredItems | Should -BeNullOrEmpty
    }
    It 'refuses forged folder count metadata despite identical paths' {
        $a=[pscustomobject]@{FolderCount=2;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=3;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=2;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=3;Subfolders=0})}
        { Compare-OPA264RestoreFolderInventories -Source $a -Restored $b } |
            Should -Throw '*inconsistent*'
    }
    It 'refuses negative item counts from a malformed snapshot' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=-1;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=0;Subfolders=0})}
        { Compare-OPA264RestoreFolderInventories -Source $a -Restored $b } |
            Should -Throw '*negative*'
    }
    It 'reports an exact match without difference records or production permission' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=26310;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $a
        $result.FolderStructureAndCountsEqual | Should -BeTrue
        $result.DifferenceCount | Should -Be 0
        $result.Differences.Count | Should -Be 0
        $result.ProductionReady | Should -BeFalse
        $result.MailMoveAllowed | Should -BeFalse
    }
    It 'does not emit subjects, sender addresses, message IDs or body fields' {
        $a=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=10;Subfolders=0})}
        $b=[pscustomobject]@{FolderCount=1;Folders=@([pscustomobject]@{RelativePath='Inbox';Items=9;Subfolders=0})}
        $result=Compare-OPA264RestoreFolderInventories -Source $a -Restored $b
        $keys=@($result.Differences[0].PSObject.Properties.Name)
        @($keys | Where-Object { $_ -in @('Subject','Sender','Body','EntryId','InternetMessageId') }).Count |
            Should -Be 0
    }

}
