#requires -Version 5.1
# BW4k0: validate a freshly selected disposable POP3 Inbox MailItem.
# Pure read-only scope gate. Never sends, saves, deletes or moves mail.
. (Join-Path $PSScriptRoot 'BW4jSuitePlan265.ps1')

function Assert-OPA265BW4k0SelectedMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][object]$Case,
        [Parameter(Mandatory=$true)][string]$ExpectedStoreId,
        [Parameter(Mandatory=$true)][string]$ExpectedInboxFolderEntryId,
        [Parameter(Mandatory=$true)][int]$SelectionCount
    )
    if ($SelectionCount -ne 1 -or [int]$Mail.Class -ne 43) {
        throw 'BW4k0 requires exactly one selected Outlook MailItem.'
    }
    $itemId=[string]$Mail.EntryID
    $folderId=[string]$Mail.Parent.EntryID
    $storeId=[string]$Mail.Parent.StoreID
    if ([string]::IsNullOrWhiteSpace($itemId) -or $itemId.Length -gt 8192 -or
        [string]::IsNullOrWhiteSpace($folderId) -or $folderId.Length -gt 8192 -or
        [string]::IsNullOrWhiteSpace($storeId) -or $storeId.Length -gt 8192 -or
        $folderId -cne $ExpectedInboxFolderEntryId -or
        $storeId -cne $ExpectedStoreId) {
        throw 'BW4k0 selected item must belong to the exact POP3 store Inbox.'
    }
    [void](Assert-OPA265BW4jFixture -Case $Case -Subject ([string]$Mail.Subject) -Body ([string]$Mail.Body) -HtmlBody ([string]$Mail.HTMLBody) -AttachmentCount ([int]$Mail.Attachments.Count))
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k0.SelectedDisposableMailScope.1'
        TestId=[string]$Case.TestId
        CaseName=[string]$Case.Name
        SourceEntryId=$itemId
        SourceFolderEntryId=$folderId
        SourceStoreId=$storeId
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
