#requires -Version 5.1
# 2.6.4-B2 DEV. Opt-in fixture creation; NO MailItem.Move or Worker launch.
[CmdletBinding()]
param([switch]$Execute,[switch]$AllowTemporaryStoreMounts)
$ErrorActionPreference='Stop'
if (-not ($Execute -and $AllowTemporaryStoreMounts)) {
    throw 'Both -Execute and -AllowTemporaryStoreMounts are required.'
}
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Fixture requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerTestFixture.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')

function Get-OPA264MountedFixtureStore {
    [CmdletBinding()]
    param([object]$Namespace,[string]$Path)
    $count=0; $matching=$null
    for ($i=1;$i -le [int]$Namespace.Stores.Count;$i++) {
        $store=$Namespace.Stores.Item($i)
        if ([string]::Equals([string]$store.FilePath,$Path,[StringComparison]::OrdinalIgnoreCase)) {
            $count++; $matching=$store
        }
    }
    if ($count -ne 1) { throw 'Fixture PST not uniquely mounted.' }
    return $matching
}

$plan=New-OPA264FixturePlan
$paths=Assert-OPA264FreshFixture -Plan $plan
$app=$null; $ns=$null; $stage='Preflight'
try {
    # Attach to existing Outlook; never start a profile or touch a donor PST.
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook must already be open in the TEST session.' }
    $ns=$app.GetNamespace('MAPI')
    $stage='Reserve new temporary directory'
    $tempRoot=Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($paths.Directory)) -Force
    if (($tempRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'TEMP root is a reparse point.'
    }
    if ([IO.Directory]::Exists($paths.Directory)) { throw 'RunId directory already exists.' }
    [void][IO.Directory]::CreateDirectory($paths.Directory)
    if ([IO.File]::Exists($paths.SourcePst) -or [IO.File]::Exists($paths.ArchivePst)) {
        throw 'PST already exists.'
    }
    $stage='Create two Unicode PSTs'
    $ns.AddStoreEx($paths.SourcePst,3)
    $ns.AddStoreEx($paths.ArchivePst,3)
    $src=Get-OPA264MountedFixtureStore -Namespace $ns -Path $paths.SourcePst
    $dst=Get-OPA264MountedFixtureStore -Namespace $ns -Path $paths.ArchivePst
    if ([string]$src.StoreID -ceq [string]$dst.StoreID) { throw 'Duplicate StoreID.' }
    $sourceFolder=$src.GetRootFolder().Folders.Add($plan.SourceFolderName)
    $targetFolder=$dst.GetRootFolder().Folders.Add($plan.ArchiveFolderName)
    if ([string]$sourceFolder.StoreID -cne [string]$src.StoreID -or
        [string]$targetFolder.StoreID -cne [string]$dst.StoreID) {
        throw 'Folder belongs to unexpected store.'
    }
    $stage='Create synthetic MailItem in NEW PST only'
    $mail=$sourceFolder.Items.Add('IPM.Note')
    if ($null -eq $mail -or [int]$mail.Class -ne 43) { throw 'Failed to create test MailItem.' }
    $messageId='<opa264-' + $paths.RunId + '@example.invalid>'
    $sender='opa264-fixture@example.invalid'
    $mail.Subject='OPA264 synthetic ' + $paths.RunId
    $mail.Body='Synthetic mail solely for disposable PST testing.'
    $mail.PropertyAccessor.SetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F',$messageId)
    $mail.PropertyAccessor.SetProperty('http://schemas.microsoft.com/mapi/proptag/0x0C1F001F',$sender)
    $mail.Save()
    if ([string]::IsNullOrWhiteSpace([string]$mail.EntryID) -or
        [string]$mail.Parent.StoreID -cne [string]$src.StoreID -or
        [string]$mail.Parent.FolderPath -cne [string]$sourceFolder.FolderPath -or
        [string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F') -cne $messageId -or
        [string]$mail.SenderEmailAddress -ine $sender -or [long]$mail.Size -le 0) {
        throw 'Outlook cannot persist required synthetic fingerprint; no Worker allowed.'
    }
    $stage='Persist Intent then request and marker'
    $request=[pscustomobject]@{
        RunId=$paths.RunId; OperationId=$plan.OperationId
        SourcePst=$paths.SourcePst; ArchivePst=$paths.ArchivePst
        JournalPath=$paths.JournalPath
        SourceStoreId=[string]$src.StoreID; ArchiveStoreId=[string]$dst.StoreID
        SourceFolderEntryId=[string]$sourceFolder.EntryID
        ArchiveFolderEntryId=[string]$targetFolder.EntryID
        SourceFolderPath=[string]$sourceFolder.FolderPath
        ArchiveFolderPath=[string]$targetFolder.FolderPath
        SourceEntryId=[string]$mail.EntryID
    }
    $journalParameters=@{
        Path=$paths.JournalPath; TransactionId=$paths.RunId; OperationId=$plan.OperationId
        Sequence=1; Phase='Intent'; OperationKind='MailMove'
        SourceEntryId=[string]$mail.EntryID; SourceStoreId=[string]$src.StoreID
        SourceFolderPath=[string]$sourceFolder.FolderPath
        TargetFolderPath=[string]$targetFolder.FolderPath
        ArchivePst=$paths.ArchivePst
        InternetMessageId=$messageId; Subject=[string]$mail.Subject
        Sender=$sender; Size=[long]$mail.Size
    }
    [void](Write-OPAOperationJournalEvent @journalParameters)
    Write-OPAWorkerJsonAtomic -Path $paths.RequestPath -Value $request
    $marker=[pscustomobject]@{
        Purpose='OPA264-Disposable-Pst-Pair'; RunId=$paths.RunId
        SourcePst=$paths.SourcePst; ArchivePst=$paths.ArchivePst
    }
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $marker -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($paths.MarkerPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    $stage='Verify read-only fixture state'
    [void](Assert-OPA264TestMoveScope -Request $request)
    [void](Assert-OPA264TestMoveIntent -Request $request -Paths $paths)
    [pscustomobject]@{
        Status='PreparedOnly'; RunId=$paths.RunId; OperationId=$plan.OperationId
        Directory=$paths.Directory; RequestFile=$paths.RequestPath
        JournalFile=$paths.JournalPath; WorkerStarted=$false; MailMoveExecuted=$false
    }
}
catch {
    throw ("Fixture stopped during {0}: {1}. Preserve disposable PSTs and logs; DO NOT run Worker against partial fixture." -f $stage,$_.Exception.Message)
}
finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
