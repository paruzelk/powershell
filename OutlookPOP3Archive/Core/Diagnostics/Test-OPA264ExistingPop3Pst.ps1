#requires -Version 5.1
<#
.SYNOPSIS
    Read-only POP3 PST scope audit inside the CURRENT Outlook profile.
.DESCRIPTION
    No new Outlook profile required. Does not create, mount or detach PSTs;
    does not create, copy, move, edit or delete any messages or folders;
    does not write journals. Refuses a target PST not uniquely associated
    with exactly one POP3 account's DeliveryStore.
.EXAMPLE
    powershell.exe -NoLogo -NoProfile -STA -File .\Test-OPA264ExistingPop3Pst.ps1 -PstPath 'C:\Test\Mailbox.pst' -Review
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PstPath,
    [switch]$Review,
    [ValidateRange(1,1000)][int]$MaxFolders=100
)
$ErrorActionPreference='Stop'
if (-not $Review) { throw 'The read-only POP3 test requires -Review.' }
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Use Windows PowerShell 5.1 STA.'
}
if (-not [IO.Path]::IsPathRooted($PstPath) -or
    $PstPath.StartsWith('\\',[StringComparison]::Ordinal) -or
    [IO.Path]::GetExtension($PstPath) -ine '.pst') {
    throw 'The target must be an absolute local .pst path.'
}
$expected=[IO.Path]::GetFullPath($PstPath)
if (-not [IO.File]::Exists($expected)) { throw 'Selected source PST does not exist.' }
if (([IO.File]::GetAttributes($expected) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Selected PST must not be a reparse point.'
}
$app=$null; $ns=$null
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook is not running.' }
    $ns=$app.GetNamespace('MAPI')
    $profile=[string]$ns.CurrentProfileName
    $pstSizeMB=[Math]::Round(([double](Get-Item -LiteralPath $expected -Force).Length / 1MB),2)
    $selected=$null
    $storeMatches=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $item=$ns.Stores.Item($i)
        $path=''
        try { $path=[string]$item.FilePath } catch { $path='' }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $canonical=''
        try { $canonical=[IO.Path]::GetFullPath($path) }
        catch { continue }
        if ([string]::Equals($canonical,$expected,
                [StringComparison]::OrdinalIgnoreCase)) {
            $selected=$item
            $storeMatches++
        }
    }
    if($storeMatches -ne 1) { throw 'Target PST is not uniquely mounted in current Outlook.' }
    $targetStoreId=[string]$selected.StoreID
    $pop3Accounts=0
    $imapAccounts=0
    $deliveryMatches=0
    $matchingAccountName=''
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $account=$ns.Accounts.Item($i)
        $type=[int]$account.AccountType
        if ($type -eq 1) { $imapAccounts++; continue }
        if ($type -ne 2) { continue }
        $pop3Accounts++
        $delivery=$null
        try { $delivery=$account.DeliveryStore }
        catch {
            throw 'Cannot safely resolve POP3 account DeliveryStore; review requires an exact POP3 mapping.'
        }
        if ($null -eq $delivery) { throw 'POP3 account DeliveryStore missing.' }
        if ([string]$delivery.StoreID -ceq $targetStoreId) {
            $deliveryMatches++
            $matchingAccountName=[string]$account.DisplayName
        }
    }
    if ($deliveryMatches -ne 1) {
        throw ('The selected PST does not map to exactly one POP3 DeliveryStore; matches={0}.' -f $deliveryMatches)
    }
    $root=$selected.GetRootFolder()
    $pending=New-Object Collections.Queue
    $pending.Enqueue([pscustomobject]@{Folder=$root;Depth=0})
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $enumerated=0
    while ($pending.Count -gt 0) {
        if ($enumerated -ge $MaxFolders) {
            throw ("Folder count exceeds MaxFolders={0}; rerun with a larger read-only limit." -f $MaxFolders)
        }
        $current=$pending.Dequeue()
        $folder=$current.Folder
        $count=[int]$folder.Items.Count
        $children=$folder.Folders
        [void]$rows.Add([pscustomobject]@{
            FolderPath=[string]$folder.FolderPath
            Depth=[int]$current.Depth
            Items=$count
            Subfolders=[int]$children.Count
        })
        $enumerated++
        for($j=1;$j -le [int]$children.Count;$j++){
            $pending.Enqueue([pscustomobject]@{
                Folder=$children.Item($j)
                Depth=([int]$current.Depth+1)
            })
        }
    }
    [pscustomobject]@{
        Schema='2.6.4-Live.ExistingPOP3.1'
        Status='ReadOnlyPOP3ScopeVerified'
        CurrentProfile=$profile
        SourcePst=$expected
        SourceStoreDisplayName=[string]$selected.DisplayName
        SourceSizeMB=$pstSizeMB
        MatchingPop3Account=$matchingAccountName
        Pop3Accounts=$pop3Accounts
        ImapAccounts=$imapAccounts
        UniquePop3DeliveryStoreMatch=$true
        FolderCount=$enumerated
        Folders=$rows.ToArray()
        MailMoveExecuted=$false
        PstCreatedOrMounted=$false
        JournalModified=$false
        ExistingPstMutationAllowed=$false
        BackupVerified=$false
        NextStep='Approve a restorable backup before synthetic message creation in this existing PST.'
    }
}
finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
