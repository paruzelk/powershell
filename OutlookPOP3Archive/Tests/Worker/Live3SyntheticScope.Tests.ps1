#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live3SyntheticScope.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-LIVE3 synthetic-only existing POP3 PST Worker contract' {
    BeforeEach {
        $src=Join-Path $TestDrive ('existing-test-'+[guid]::NewGuid().ToString('N')+'.pst')
        [IO.File]::WriteAllBytes($src,(New-Object byte[] 4096))
        $run=[guid]::NewGuid().ToString('D')
        $paths=Get-OPA264Live3Paths -RunId $run -SourcePst $src
        $op=[guid]::NewGuid().ToString('D')
        $request=[pscustomobject]@{
            RunId=$paths.RunId;OperationId=$op
            SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            JournalPath=$paths.JournalPath
            SourceStoreId='POP3-TEST-STORE';ArchiveStoreId='NEW-TEST-STORE'
            SourceFolderEntryId='SOURCE-FOLDER-ID';ArchiveFolderEntryId='TARGET-FOLDER-ID'
            SourceFolderPath=('\\SyntheticPST\'+$paths.SourceFolderName)
            ArchiveFolderPath=('\\TemporaryArchive\'+$paths.ArchiveFolderName)
            SourceEntryId='SYNTHETIC-ONLY-ENTRY'
        }
    }
    AfterEach {
        if($null -ne $paths -and [IO.Directory]::Exists($paths.Directory)){
            [IO.Directory]::Delete($paths.Directory,$true)
        }
    }
    It 'generates fixed run-unique temporary archive path' {
        $paths.ArchivePst | Should -Match 'OPA264-LIVE3-[0-9a-f]{32}'
        [IO.Path]::GetFileName($paths.ArchivePst) | Should -Be 'Archive.pst'
    }
    It 'generates distinct source and archive synthetic folder names' {
        $paths.SourceFolderName | Should -Match 'OPA264-LIVE3-[0-9a-f]{32}$'
        $paths.ArchiveFolderName | Should -Match 'OPA264-LIVE3-Archive-[0-9a-f]{32}$'
        $paths.SourceFolderName | Should -Not -Be $paths.ArchiveFolderName
    }
    It 'refuses invalid RunId' {
        {Get-OPA264Live3Paths -RunId 'no-guid' -SourcePst $src} | Should -Throw '*GUID*'
    }
    It 'refuses missing source PST path' {
        {Get-OPA264Live3Paths -RunId $run -SourcePst (Join-Path $TestDrive 'missing.pst')} |
            Should -Throw '*missing*'
    }
    It 'refuses non-PST source file extension' {
        {Get-OPA264Live3Paths -RunId $run -SourcePst (Join-Path $TestDrive 'some.txt')} |
            Should -Throw '*local absolute*'
    }
    It 'refuses network file root' {
        {Get-OPA264Live3Paths -RunId $run -SourcePst '\\server\share\mail.pst'} |
            Should -Throw '*local absolute*'
    }
    It 'accepts a never-used RunId directory' {
        (Assert-OPA264Live3Fresh -Paths $paths) | Should -BeTrue
    }
    It 'refuses any existing TEMP run directory' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        {Assert-OPA264Live3Fresh -Paths $paths} | Should -Throw '*already exists*'
    }
    It 'refuses missing durable marker and journal' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        [IO.File]::WriteAllBytes($paths.ArchivePst,(New-Object byte[] 2048))
        {Assert-OPA264Live3Request -Request $request} | Should -Throw '*missing*'
    }
    It 'rejects an archive path outside unique TEMP scope before COM' {
        $request.ArchivePst=$src
        {Assert-OPA264Live3Request -Request $request} | Should -Throw '*outside exact scope*'
    }
    It 'rejects a real Inbox folder as synthetic source' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        [IO.File]::WriteAllBytes($paths.ArchivePst,(New-Object byte[] 2048))
        [IO.File]::WriteAllText($paths.ScopePath,
            ('{"Purpose":"OPA264-LIVE3-OneSyntheticMail","RunId":"' + $paths.RunId +
             '","SourcePst":"' + $paths.SourcePst.Replace('\','\\') +
             '","ArchivePst":"' + $paths.ArchivePst.Replace('\','\\') +
             '","SourceFolderName":"' + $paths.SourceFolderName +
             '","ArchiveFolderName":"' + $paths.ArchiveFolderName +
             '","AllowExistingMailMove":false}'))
        [IO.File]::WriteAllText($paths.JournalPath,'')
        $request.SourceFolderPath='\\SyntheticPST\Inbox'
        {Assert-OPA264Live3Request -Request $request} | Should -Throw '*exact synthetic*'
    }
    It 'requires a recognized OperationId GUID' {
        $request.OperationId='not-an-operation-guid'
        {Assert-OPA264Live3Request -Request $request} | Should -Throw '*OperationId*'
    }
    It 'rejects source/target StoreID collision by design' {
        $request.ArchiveStoreId=$request.SourceStoreId
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        [IO.File]::WriteAllBytes($paths.ArchivePst,(New-Object byte[] 2048))
        $marker=[pscustomobject]@{
            Purpose='OPA264-LIVE3-OneSyntheticMail'
            RunId=$paths.RunId;SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            SourceFolderName=$paths.SourceFolderName;ArchiveFolderName=$paths.ArchiveFolderName
            AllowExistingMailMove=$false
        }
        [IO.File]::WriteAllText($paths.ScopePath,(ConvertTo-Json -InputObject $marker))
        [IO.File]::WriteAllText($paths.JournalPath,'')
        {Assert-OPA264Live3Request -Request $request} | Should -Throw '*StoreID*'
    }
    It 'forbids fixture creator from invoking MailItem.Move' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264Live3SyntheticFixture.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -eq 'Move'}).Count | Should -Be 0
    }
    It 'allows exactly one Move method invocation in dedicated test Worker' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live3SyntheticWorker.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -eq 'Move'}).Count | Should -Be 1
    }
    It 'forbids Move and PST detach in independent read-only inspector' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA264Live3SyntheticMove.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -in @(
            'Move','AddStoreEx','AddStore','RemoveStore','Delete','Save','Kill'
        )}).Count | Should -Be 0
    }
    It 'does not authorize normal production Worker MailMove operation' {
        $file=Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1'
        $raw=Get-Content -LiteralPath $file -Raw
        $raw | Should -Not -Match "'MailMove'"
    }
    It 'fixture never requires SenderEmailAddress from locally created unsent MailItem' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264Live3SyntheticFixture.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Not -Match '\$mail\.SenderEmailAddress'
    }
    It 'fixture never sets sender MAPI proptag on unsent synthetic item' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264Live3SyntheticFixture.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Not -Match '0x0C1F001F'
    }
    It 'LIVE3 Worker verifies synthetic identifiers without SenderEmailAddress' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live3SyntheticWorker.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Not -Match '\$mail\.SenderEmailAddress'
        $txt | Should -Match '0x1035001F'
        $txt | Should -Match 'SourceEntryId'
    }
    It 'LIVE3 Worker does not require identical MailItem Size across Outlook stores' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live3SyntheticWorker.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Not -Match '\$mail\.Size -ne '
    }
    It 'read-only inspector does not require sender or equal Size after cross-PST Move' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA264Live3SyntheticMove.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Not -Match '\$item\.SenderEmailAddress'
        $txt | Should -Not -Match '\$item\.Size -ne '
    }
    It 'fixture reports which identity assertion failed without permitting a Move' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264Live3SyntheticFixture.ps1'
        $txt=Get-Content -LiteralPath $file -Raw
        $txt | Should -Match 'MissingSourceEntryID'
        $txt | Should -Match 'InternetMessageIdMismatch'
        $txt | Should -Match 'UnexpectedParentFolder'
        $txt | Should -Match 'LIVE3 synthetic identity failed'
    }
    It 'journal Intent accepts an unsent synthetic test item with zero Size and no sender' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        $intentParams=@{
            Path=$paths.JournalPath
            TransactionId=$paths.RunId
            OperationId=$request.OperationId
            Sequence=1
            Phase='Intent'
            OperationKind='MailMove'
            SourceEntryId=$request.SourceEntryId
            SourceStoreId=$request.SourceStoreId
            SourceFolderPath=$request.SourceFolderPath
            TargetFolderPath=$request.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId=('<opa264-live3-'+$paths.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+$paths.RunId)
            Sender=''
            Size=[long]0
        }
        [void](Write-OPAOperationJournalEvent @intentParams)
        $observed=Assert-OPA264Live3Intent -Request $request -Paths $paths
        $observed.Subject | Should -Be ('OPA264 LIVE3 synthetic '+$paths.RunId)
        $observed.Size | Should -Be 0
    }
    It 'journal Intent rejects a foreign Subject even if EntryId matches' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        $intentParams=@{
            Path=$paths.JournalPath;TransactionId=$paths.RunId;OperationId=$request.OperationId
            Sequence=1;Phase='Intent';OperationKind='MailMove'
            SourceEntryId=$request.SourceEntryId;SourceStoreId=$request.SourceStoreId
            SourceFolderPath=$request.SourceFolderPath;TargetFolderPath=$request.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId=('<opa264-live3-'+$paths.RunId+'@example.invalid>')
            Subject='Some other mail';Sender='';Size=0
        }
        [void](Write-OPAOperationJournalEvent @intentParams)
        {Assert-OPA264Live3Intent -Request $request -Paths $paths} |
            Should -Throw '*synthetic request*'
    }
    It 'journal Intent rejects a foreign MessageId even when Subject matches' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        $intentParams=@{
            Path=$paths.JournalPath;TransactionId=$paths.RunId;OperationId=$request.OperationId
            Sequence=1;Phase='Intent';OperationKind='MailMove'
            SourceEntryId=$request.SourceEntryId;SourceStoreId=$request.SourceStoreId
            SourceFolderPath=$request.SourceFolderPath;TargetFolderPath=$request.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId='<not-this-run@example.invalid>'
            Subject=('OPA264 LIVE3 synthetic '+$paths.RunId);Sender='';Size=0
        }
        [void](Write-OPAOperationJournalEvent @intentParams)
        {Assert-OPA264Live3Intent -Request $request -Paths $paths} |
            Should -Throw '*synthetic request*'
    }
    It 'journal Intent rejects negative synthetic Size metadata' {
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        $intentParams=@{
            Path=$paths.JournalPath;TransactionId=$paths.RunId;OperationId=$request.OperationId
            Sequence=1;Phase='Intent';OperationKind='MailMove'
            SourceEntryId=$request.SourceEntryId;SourceStoreId=$request.SourceStoreId
            SourceFolderPath=$request.SourceFolderPath;TargetFolderPath=$request.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId=('<opa264-live3-'+$paths.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+$paths.RunId);Sender='';Size=-1
        }
        [void](Write-OPAOperationJournalEvent @intentParams)
        {Assert-OPA264Live3Intent -Request $request -Paths $paths} |
            Should -Throw '*synthetic request*'
    }

}
