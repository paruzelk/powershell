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
}
