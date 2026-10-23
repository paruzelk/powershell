#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/ExistingPstBackupGuard.ps1')
}
Describe '2.6.4-LIVE1 existing POP3 PST backup safety (synthetic files only)' {
    BeforeEach {
        $base=Join-Path $TestDrive ('OPA264-'+[guid]::NewGuid().ToString('N'))
        $sourceDirectory=Join-Path $base 'Outlook'
        $backupDirectory=Join-Path $base 'Backup'
        [void][IO.Directory]::CreateDirectory($sourceDirectory)
        [void][IO.Directory]::CreateDirectory($backupDirectory)
        $source=Join-Path $sourceDirectory 'synthetic.pst'
        $backup=Join-Path $backupDirectory 'synthetic-lab-backup.pst'
        [IO.File]::WriteAllBytes($source,(New-Object byte[] 2048))
    }
    It 'accepts a new, distinct backup destination' {
        $r=Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $backup
        $r.SourceSizeBytes | Should -Be 2048
        $r.BackupVerified | Should -BeFalse
        $r.ExistingPstMoveAuthorized | Should -BeFalse
    }
    It 'never overwrites an existing destination backup' {
        [IO.File]::WriteAllBytes($backup,(New-Object byte[] 2048))
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $backup } | Should -Throw '*already exists*'
    }
    It 'never resumes or clobbers a partial backup' {
        [IO.File]::WriteAllText(($backup+'.opa264-partial'),'partial')
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $backup } | Should -Throw '*partial file already exists*'
    }
    It 'rejects source same as backup destination' {
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $source } | Should -Throw '*must differ*'
    }
    It 'refuses placing backup beside a live Outlook PST' {
        $sameDir=Join-Path $sourceDirectory 'backup.pst'
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $sameDir } | Should -Throw '*OUTSIDE*'
    }
    It 'refuses placing a backup in a nested Outlook data directory' {
        $sub=Join-Path $sourceDirectory 'old'
        [void][IO.Directory]::CreateDirectory($sub)
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst (Join-Path $sub 'backup.pst') } | Should -Throw '*OUTSIDE*'
    }
    It 'rejects missing source PST' {
        { Get-OPA264ExistingPstBackupPlan -SourcePst (Join-Path $sourceDirectory 'missing.pst') -BackupPst $backup } | Should -Throw '*does not exist*'
    }
    It 'rejects tiny or empty source PST files' {
        [IO.File]::WriteAllBytes($source,([byte[]]@(1,2,3)))
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $backup } | Should -Throw '*small*'
    }
    It 'rejects backup parent directory that is not present' {
        $path=Join-Path (Join-Path $base 'MissingDirectory') 'backup.pst'
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $path } | Should -Throw
    }
    It 'refuses UNC destinations' {
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst '\\server\share\backup.pst' } | Should -Throw '*local*'
    }
    It 'refuses non-PST targets' {
        { Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst (Join-Path $backupDirectory 'backup.dat') } | Should -Throw '*PST*'
    }
    It 'accepts a review plan without writing a backup file' {
        $r=Get-OPA264ExistingPstBackupPlan -SourcePst $source -BackupPst $backup
        $r.OutlookMustBeClosed | Should -BeTrue
        [IO.File]::Exists($backup) | Should -BeFalse
        [IO.File]::Exists($backup+'.opa264-partial') | Should -BeFalse
    }
    It 'forbids Outlook store mutation, process termination and mail method calls in backup CLI' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264ExistingPstBackup.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {
            [string]$_.Member.Value -in @('Delete','Kill','AddStore','AddStoreEx','RemoveStore','Quit')
        }).Count | Should -Be 0
        $raw=Get-Content -LiteralPath $path -Raw
        $raw | Should -Not -Match '\$mail\.Move\('
    }
    It 'requires an explicit create mode and fixed approval token' {
        $scriptText=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264ExistingPstBackup.ps1') -Raw
        $scriptText | Should -Match '\$CreateBackup -and \$ApprovalToken -cne '
        $scriptText | Should -Match "'BACKUP-OPA264-EXISTING-PST'"
        $scriptText | Should -Match '\[IO\.FileMode\]::CreateNew'
    }
}
