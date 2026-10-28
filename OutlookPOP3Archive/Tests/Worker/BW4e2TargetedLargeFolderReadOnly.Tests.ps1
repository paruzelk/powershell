#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1')
    function Invoke-BW4e2MockTarget {
        Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId '0011AABB' -CandidateEntryId '00AACCEE' -MaxFolderItems 1000 -UseTargetedMessageIdReadOnly
    }
}
Describe 'BW4e2 bounded targeted exact MAPI InternetMessageId read-only lookup' {
    BeforeEach {
        $script:pst=Join-Path $TestDrive 'BW4e2-test.pst'
        [IO.File]::WriteAllBytes($script:pst,[byte[]](1,2))
        $script:store=[pscustomobject]@{FilePath=$script:pst;StoreID='00AABBCC'}
        $script:stores=[pscustomobject]@{Count=1;Rows=@($script:store)}
        $script:stores | Add-Member ScriptMethod Item {param($n) $this.Rows[$n-1]}
        $script:acct=[pscustomobject]@{AccountType=2;DeliveryStore=$script:store}
        $script:accounts=[pscustomobject]@{Count=1;Rows=@($script:acct)}
        $script:accounts | Add-Member ScriptMethod Item {param($n) $this.Rows[$n-1]}
        $script:folder=[pscustomobject]@{EntryID='0011aabb';StoreID='00aabbcc';Items=$null}
        $script:pa=[pscustomobject]@{MessageId='<fresh-bw4e2-20261028@example.invalid>';Key=[byte[]](1,2,3)}
        $script:pa | Add-Member ScriptMethod GetProperty {
            param($name)
            if ($name -eq 'http://schemas.microsoft.com/mapi/proptag/0x1035001F'){return $this.MessageId}
            if ($name -eq 'http://schemas.microsoft.com/mapi/proptag/0x300B0102'){return $this.Key}
            throw 'Unexpected property'
        }
        $script:mail=[pscustomobject]@{
            Class=43;EntryID='00aaccee';Parent=$script:folder;PropertyAccessor=$script:pa
            Size=[long]1444;ReceivedTime=[datetime]'2026-10-28T11:00:00'
            Subject='Fresh BW4e2 candidate';SenderEmailAddress='test@example.invalid';Body='new synthetic'
        }
        $script:restricted=[pscustomobject]@{Count=1;Target=$script:mail}
        $script:restricted | Add-Member ScriptMethod Item {
            param($n)
            if ($n -ne 1) { throw 'Out-of-range filtered item' }
            return $this.Target
        }
        $script:items=[pscustomobject]@{
            Count=26485
            Restricted=$script:restricted
            Filter=''
            ThrowOnRestrict=$false
            FullEnumerationAttempts=0
        }
        $script:items | Add-Member ScriptMethod Restrict {
            param($sql)
            $this.Filter=$sql
            if ($this.ThrowOnRestrict){throw 'MAPI restriction unsupported'}
            return $this.Restricted
        }
        $script:items | Add-Member ScriptMethod Item {
            param($n)
            $this.FullEnumerationAttempts++
            throw 'BW4e2 must NOT enumerate the large original Inbox'
        }
        $script:folder.Items=$script:items
        $script:ns=[pscustomobject]@{Stores=$script:stores;Accounts=$script:accounts;Folder=$script:folder;Target=$script:mail}
        $script:ns | Add-Member ScriptMethod GetFolderFromID {param($id,$store) $this.Folder}
        $script:ns | Add-Member ScriptMethod GetItemFromID {param($id,$store) $this.Target}
    }
    It 'accepts one exact matching InternetMessageId among 26485 messages without enumerating Inbox' {
        $r=Invoke-BW4e2MockTarget
        $r.TargetedMessageIdReadOnlyUsed | Should -BeTrue
        $r.FolderItemsObserved | Should -Be 26485
        $r.FolderItemsScanned | Should -Be 0
        $r.CandidateMatches | Should -Be 1
        $script:items.FullEnumerationAttempts | Should -Be 0
        $r.MailMoveExecuted | Should -BeFalse
    }
    It 'generates exact-quoted DASL MAPI Unicode InternetMessageId equality restriction' {
        $r=Invoke-BW4e2MockTarget
        $script:items.Filter | Should -BeExactly ('@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = ' + "'<fresh-bw4e2-20261028@example.invalid>'")
    }
    It 'returns same MAPI search-key and content hashes from two read paths' {
        $r=Invoke-BW4e2MockTarget
        $r.Primary.SearchKeySha256 | Should -BeExactly $r.Independent.SearchKeySha256
        $r.Primary.ContentSha256 | Should -BeExactly $r.Independent.ContentSha256
        $r.IndependentExternalMAPIProof | Should -BeFalse
    }
    It 'refuses the same folder through legacy 1000-item bounded enumeration' {
        {Get-OPA265BW4cDualReadback -Namespace $script:ns -SourcePst $script:pst -FolderEntryId '0011AABB' -CandidateEntryId '00AACCEE' -MaxFolderItems 1000} | Should -Throw '*folder cardinality outside explicit scan cap*'
        $script:items.Filter | Should -BeExactly ''
    }
    It 'rejects zero matching InternetMessageId values' {
        $script:restricted.Count=0
        {Invoke-BW4e2MockTarget} | Should -Throw '*must return ONE item*'
    }
    It 'rejects duplicate InternetMessageId values' {
        $script:restricted.Count=2
        {Invoke-BW4e2MockTarget} | Should -Throw '*must return ONE item*'
    }
    It 'rejects null MAPI Restrict result with no fallback' {
        $script:items.Restricted=$null
        {Invoke-BW4e2MockTarget} | Should -Throw '*Restrict returned null*'
    }
    It 'rejects unsupported Outlook Restrict with no full Inbox enumeration' {
        $script:items.ThrowOnRestrict=$true
        {Invoke-BW4e2MockTarget} | Should -Throw '*restriction failed closed*'
        $script:items.FullEnumerationAttempts | Should -Be 0
    }
    It 'rejects restricted result with a different EntryID' {
        $script:restricted.Target=[pscustomobject]@{EntryID='00AACCFF'}
        {Invoke-BW4e2MockTarget} | Should -Throw '*different EntryID*'
    }
    It 'rejects different store on direct candidate' {
        $script:folder.StoreID='ABCD0011'
        {Invoke-BW4e2MockTarget} | Should -Throw
    }
    It 'rejects absence of a POP3 account' {
        $script:acct.AccountType=1
        {Invoke-BW4e2MockTarget} | Should -Throw
    }
    It 'rejects an empty large folder despite valid direct object' {
        $script:items.Count=0
        {Invoke-BW4e2MockTarget} | Should -Throw '*folder count outside targeted-read-only guard*'
    }
    It 'rejects an Inbox above explicit 100000 message guard' {
        $script:items.Count=100001
        {Invoke-BW4e2MockTarget} | Should -Throw '*folder count outside targeted-read-only guard*'
    }
    It 'refuses missing InternetMessageId before invoking Restrict' {
        $script:pa.MessageId=''
        {Invoke-BW4e2MockTarget} | Should -Throw
        $script:items.Filter | Should -BeExactly ''
    }
    It 'refuses quoted InternetMessageId rather than constructing an unsafe query' {
        $script:pa.MessageId="<bad'@example.invalid>"
        {Invoke-BW4e2MockTarget} | Should -Throw '*not safe for exact DASL filtering*'
        $script:items.Filter | Should -BeExactly ''
    }
    It 'refuses whitespace in the direct InternetMessageId' {
        $script:pa.MessageId='<bad id@example.invalid>'
        {Invoke-BW4e2MockTarget} | Should -Throw '*not safe for exact DASL filtering*'
    }
    It 'refuses mismatched second-read search key' {
        $secondPa=[pscustomobject]@{MessageId=$script:pa.MessageId;Key=[byte[]](4,5,6)}
        $secondPa | Add-Member ScriptMethod GetProperty {
            param($name)
            if ($name -like '*0x1035001F'){return $this.MessageId}
            if ($name -like '*0x300B0102'){return $this.Key}
            throw 'bad prop'
        }
        $second=$script:mail.PSObject.Copy()
        $second.PropertyAccessor=$secondPa
        $script:restricted.Target=$second
        {Invoke-BW4e2MockTarget} | Should -Throw '*readbacks disagree*'
    }
    It 'refuses mismatched second-read body fingerprint' {
        $second=$script:mail.PSObject.Copy()
        $second.Body='changed from another Outlook COM route'
        $script:restricted.Target=$second
        {Invoke-BW4e2MockTarget} | Should -Throw '*readbacks disagree*'
    }
}
