#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k0SelectedScope265.ps1')
    function New-BW4k0MockMail {
        param([object]$Case)
        [pscustomobject]@{
            Class=43
            EntryID='ABCDEF1234'
            Parent=[pscustomobject]@{EntryID='F01234';StoreID='AABBCC'}
            Subject=[string]$Case.Subject
            Body=([string]$Case.Marker+' test message')
            HTMLBody='<html><body>Test</body></html>'
            Attachments=[pscustomobject]@{Count=[int]$Case.ExpectedAttachmentCount}
        }
    }
}
Describe 'BW4k0 five-real-fixture operator selection is fail-closed and read-only' {
    BeforeEach {
        $script:plan=New-OPA265BW4jPlan
        $script:case=$script:plan.Cases[0]
        $script:mail=New-BW4k0MockMail -Case $script:case
    }
    It 'accepts exactly one planned synthetic message in the correct POP3 Inbox' {
        $r=Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1
        $r.TestId | Should -BeExactly $script:case.TestId
        $r.SourceEntryId | Should -BeExactly 'ABCDEF1234'
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.CanRetryMove | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'accepts the planned Cyrillic plain text fixture' {
        $case=$script:plan.Cases[1]
        $mail=New-BW4k0MockMail -Case $case
        $mail.Body+=' Привет, проверка Unicode.'
        (Assert-OPA265BW4k0SelectedMail -Mail $mail -Case $case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1).CaseName | Should -BeExactly 'UnicodePlain'
    }
    It 'accepts bounded HTML synthetic fixture metadata' {
        $case=$script:plan.Cases[2]
        $mail=New-BW4k0MockMail -Case $case
        (Assert-OPA265BW4k0SelectedMail -Mail $mail -Case $case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1).CaseName | Should -BeExactly 'HtmlBody'
    }
    It 'rejects subject not identical to immutable plan' {
        $script:mail.Subject='Unrelated real correspondence'
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1} | Should -Throw '*fixture subject*'
    }
    It 'rejects absent disposable TestId marker' {
        $script:mail.Body='No test marker'
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1} | Should -Throw '*fixture subject*'
    }
    It 'rejects a different Outlook store, including IMAP' {
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'OTHERSTORE' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1} | Should -Throw '*exact POP3 store Inbox*'
    }
    It 'rejects a user folder outside the POP3 Inbox' {
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'WRONGINBOX' -SelectionCount 1} | Should -Throw '*exact POP3 store Inbox*'
    }
    It 'rejects selecting multiple Outlook items' {
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 2} | Should -Throw '*exactly one*'
    }
    It 'rejects selecting a non-mail Outlook object' {
        $script:mail.Class=26
        {Assert-OPA265BW4k0SelectedMail -Mail $script:mail -Case $script:case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1} | Should -Throw '*MailItem*'
    }
    It 'rejects a missing planned attachment' {
        $case=$script:plan.Cases[3]
        $mail=New-BW4k0MockMail -Case $case
        $mail.Attachments.Count=0
        {Assert-OPA265BW4k0SelectedMail -Mail $mail -Case $case -ExpectedStoreId 'AABBCC' -ExpectedInboxFolderEntryId 'F01234' -SelectionCount 1} | Should -Throw '*attachment count*'
    }
}
