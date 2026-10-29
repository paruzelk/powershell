#requires -Version 5.1
BeforeAll { . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1') }
Describe 'BW4c dual-path Outlook MAPI read-only capture' {
    BeforeEach {
        $script:pst=Join-Path $TestDrive 'source.pst'
        [IO.File]::WriteAllBytes($script:pst,[byte[]](1,2))
        $script:store=[pscustomobject]@{FilePath=$script:pst;StoreID='STORE-POP3'}
        $script:stores=[pscustomobject]@{Count=1;Rows=@($script:store)}
        $script:stores | Add-Member ScriptMethod Item {param($n) $this.Rows[$n-1]}
        $script:account=[pscustomobject]@{AccountType=2;DeliveryStore=$script:store}
        $script:accounts=[pscustomobject]@{Count=1;Rows=@($script:account)}
        $script:accounts | Add-Member ScriptMethod Item {param($n) $this.Rows[$n-1]}
        $script:folder=[pscustomobject]@{EntryID='FOLDER';StoreID='STORE-POP3';Items=$null}
        $script:pa=[pscustomobject]@{MessageId='<new@example.invalid>';Key=[byte[]](1,2,3)}
        $script:pa | Add-Member ScriptMethod GetProperty {
            param($name)
            if($name -like '*0x1035001F'){return $this.MessageId}
            if($name -like '*0x300B0102'){return $this.Key}
            throw 'Unexpected property'
        }
        $script:mail=[pscustomobject]@{
            Class=43;EntryID='ITEM';Parent=$script:folder;PropertyAccessor=$script:pa
            Size=[long]1444;ReceivedTime=[datetime]'2026-10-26T09:00:00'
            Subject='Candidate';SenderEmailAddress='sender@example.invalid';Body='Test'
        }
        $script:items=[pscustomobject]@{Count=1;Rows=@($script:mail)}
        $script:items | Add-Member ScriptMethod Item {param($n) $this.Rows[$n-1]}
        $script:folder.Items=$script:items
        $script:ns=[pscustomobject]@{Stores=$script:stores;Accounts=$script:accounts;Folder=$script:folder;Target=$script:mail}
        $script:ns | Add-Member ScriptMethod GetFolderFromID {param($id,$storeId) $this.Folder}
        $script:ns | Add-Member ScriptMethod GetItemFromID {param($id,$storeId) $this.Target}
    }
    It 'reads twice and records same-store identical fingerprints without a permit' {
        $r=Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'
        $r.TwoSeparateOutlookReadPaths | Should -BeTrue
        $r.IndependentExternalMAPIProof | Should -BeFalse
        $r.Primary.ContentSha256 | Should -BeExactly $r.Independent.ContentSha256
        $r.Primary.SearchKeySha256 | Should -BeExactly $r.Independent.SearchKeySha256
        $r.Primary.CaptureId | Should -Not -Be $r.Independent.CaptureId
        $r.MailMoveExecuted | Should -BeFalse
    }
    It 'uses exactly BW4b witness schema and never prints Body' {
        $r=Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'
        $r.Primary.Schema | Should -BeExactly '2.6.5-BW4b.PerItemWitness.1'
        @($r.Primary.PSObject.Properties.Name).Count | Should -Be 12
        $r.Primary.PSObject.Properties.Name | Should -Contain 'IsExactOperatorFixture'
        $r.Primary.PSObject.Properties.Name | Should -Contain 'ObservedOperatorTestId'
        $r.Primary.PSObject.Properties.Name | Should -Not -Contain 'Body'
    }
    It 'refuses wrong folder ID' {
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'WRONG' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses wrong message ID' {
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'WRONG'} | Should -Throw
    }
    It 'refuses another store on folder' {
        $script:folder.StoreID='IMAP-STORE'
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses a target PST without a POP3 account' {
        $script:account.AccountType=1
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses two matching POP3 delivery accounts' {
        $script:accounts.Count=2;$script:accounts.Rows=@($script:account,$script:account)
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses duplicate mounted PST matches' {
        $script:stores.Count=2;$script:stores.Rows=@($script:store,$script:store)
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses a missing direct MAPI item' {
        $script:ns.Target=$null
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses too many folder items without partial proof' {
        $script:items.Count=2
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM' -MaxFolderItems 1} | Should -Throw
    }
    It 'refuses missing independent folder enumeration result' {
        $script:items.Rows=@([pscustomobject]@{EntryID='DIFFERENT'})
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses duplicate matches in enumerated folder' {
        $script:items.Count=2;$script:items.Rows=@($script:mail,$script:mail)
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses non-mail MAPI class' {
        $script:mail.Class=45
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses missing InternetMessageId' {
        $script:pa.MessageId=''
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses missing PR_SEARCH_KEY' {
        $script:pa.Key=$null
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses invalid MAPI item Size' {
        $script:mail.Size=0
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'refuses missing PST on disk' {
        [IO.File]::Delete($script:pst)
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw
    }
    It 'returns SHA256 for abc' {
        (Get-OPA265BW4cHash -Bytes ([byte[]](97,98,99))) | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
    It 'accepts identical hexadecimal folder EntryID with different letter casing' {
        $script:folder.EntryID='00aabbcc'
        $r=Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId '00AABBCC' -CandidateEntryId 'ITEM'
        $r.CandidateMatches | Should -Be 1
        $r.MailMoveExecuted | Should -BeFalse
    }
    It 'accepts identical hexadecimal StoreID despite casing from different Outlook COM routes' {
        $script:store.StoreID='00AABBCC'
        $script:folder.StoreID='00aabbcc'
        $r=Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'
        $r.CandidateMatches | Should -Be 1
        $r.MailMoveExecuted | Should -BeFalse
    }
    It 'accepts identical hexadecimal MailItem EntryID from two routes with different letter casing' {
        $script:mail.EntryID='aa11bb22'
        $r=Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'AA11BB22'
        $r.Primary.SourceEntryId | Should -BeExactly 'AA11BB22'
        $r.MailMoveExecuted | Should -BeFalse
    }
    It 'does not equate genuinely different folder EntryIDs and reports the failed check' {
        $script:folder.EntryID='00aabbcd'
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId '00AABBCC' -CandidateEntryId 'ITEM'} | Should -Throw '*folder EntryID mismatch*'
    }
    It 'does not equate genuinely different StoreIDs and reports the failed check' {
        $script:folder.StoreID='00AABBCE'
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw '*StoreID mismatch*'
    }
    It 'reports missing folder from explicit MAPI store without silent fallback' {
        $script:ns.Folder=$null
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId 'FOLDER' -CandidateEntryId 'ITEM'} | Should -Throw '*returned null*'
    }

}
