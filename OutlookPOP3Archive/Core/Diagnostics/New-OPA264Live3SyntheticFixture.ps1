#requires -Version 5.1
# LIVE3: create ONE synthetic mail in existing user-designated test POP3 PST
# and a NEW disposable destination Archive.pst. A staging Move of ONLY the
# newly saved synthetic draft may be required by Outlook; no archive Move.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [switch]$Execute,
    [switch]$ConfirmTestOnlyPst
)
$ErrorActionPreference='Stop'
if(-not ($Execute -and $ConfirmTestOnlyPst)){
    throw 'LIVE3 requires -Execute and -ConfirmTestOnlyPst.'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'LIVE3 fixture requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
$id=[guid]::NewGuid().ToString('D')
$operation=[guid]::NewGuid().ToString('D')
$paths=Get-OPA264Live3Paths -RunId $id -SourcePst $SourcePst
[void](Assert-OPA264Live3Fresh -Paths $paths)
$app=$null;$ns=$null;$stage='Outlook preflight'
try{
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'Already-running test Outlook is required.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'LIVE3 only supports the previously validated Outlook test profile.'
    }
    $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
    if([string]$src.StoreID -ceq [string]$ns.DefaultStore.StoreID){
        throw 'LIVE3 source POP3 PST must be distinct from the default store.'
    }
    $temp=Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($paths.Directory)) -Force
    if(($temp.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'LIVE3 system TEMP root must not be a reparse point.'
    }
    $stage='Create unique run directory'
    [void](Assert-OPA264Live3Fresh -Paths $paths)
    [void][IO.Directory]::CreateDirectory($paths.Directory)
    if([IO.File]::Exists($paths.ArchivePst)){throw 'LIVE3 Archive.pst already exists.'}
    $stage='Mount NEW disposable archive PST'
    $ns.AddStoreEx($paths.ArchivePst,2)
    $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    if([string]$dst.StoreID -ceq [string]$src.StoreID -or
       [string]$dst.StoreID -ceq [string]$ns.DefaultStore.StoreID){
        throw 'LIVE3 created archive does not have distinct nondefault identity.'
    }
    $stage='Create unique synthetic source/target folders'
    $srcFolder=$src.GetRootFolder().Folders.Add($paths.SourceFolderName)
    $dstFolder=$dst.GetRootFolder().Folders.Add($paths.ArchiveFolderName)
    if([string]$srcFolder.StoreID -cne [string]$src.StoreID -or
        [string]$dstFolder.StoreID -cne [string]$dst.StoreID){
        throw 'LIVE3 synthetic folder is associated with wrong store.'
    }
    if([int]$srcFolder.Items.Count -ne 0 -or
       [int]$dstFolder.Items.Count -ne 0){
        throw 'LIVE3 synthetic test folders must initially be empty.'
    }
    $stage='Create ONE synthetic MailItem'
    $mail=$srcFolder.Items.Add('IPM.Note')
    if($null -eq $mail -or [int]$mail.Class -ne 43){
        throw 'LIVE3 synthetic Outlook MailItem creation failed.'
    }
    $messageId='<opa264-live3-'+$paths.RunId+'@example.invalid>'
    $sender='opa264-live3@example.invalid'
    $subject='OPA264 LIVE3 synthetic '+$paths.RunId
    $mail.Subject=$subject
    $mail.Body='Synthetic LIVE3 diagnostic email; no user content.'
    $mail.PropertyAccessor.SetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F',$messageId)
    $mail.Save()
    # Outlook MailItem.Save() for a NEW unsent mail may store the item
    # in its default Drafts folder, not in the Items.Add() folder.
    # Inspect the exact new GUID-stamped item before any staging Move.
    # This Move is fixture setup ONLY, distinct from the later one-shot
    # cross-PST Worker Move whose Intent is persisted below.
    $stage='Verify saved synthetic identity'
    $problems=New-Object 'System.Collections.Generic.List[string]'
    if([string]::IsNullOrWhiteSpace([string]$mail.EntryID)){
        [void]$problems.Add('MissingSourceEntryID')
    }
    if([int]$mail.Class -ne 43){[void]$problems.Add('MailClassNot43')}
    if([string]$mail.Subject -cne $subject){
        [void]$problems.Add('SubjectMismatch')
    }
    $observedId=[string]$mail.PropertyAccessor.GetProperty(
        'http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if($observedId -cne $messageId){
        [void]$problems.Add('InternetMessageIdMismatch')
    }
    if($problems.Count -gt 0){
        throw ('LIVE3 synthetic identity failed: '+($problems.ToArray() -join ', '))
    }
    $stagingMoveExecuted=$false
    $parent=$mail.Parent
    if(-not (Test-OPA264Live3FolderIdentity `
        -ObservedStoreId ([string]$parent.StoreID) `
        -ObservedFolderEntryId ([string]$parent.EntryID) `
        -ExpectedStoreId ([string]$src.StoreID) `
        -ExpectedFolderEntryId ([string]$srcFolder.EntryID))){
        $stage='Place saved synthetic draft into exact test folder'
        if([int]$srcFolder.Items.Count -ne 0 -or
           [int]$dstFolder.Items.Count -ne 0){
            throw 'LIVE3 cannot stage synthetic draft into a nonempty test folder.'
        }
        $staged=$mail.Move($srcFolder)
        if($null -eq $staged){
            throw 'LIVE3 fixture staging Move did not return the item.'
        }
        $mail=$staged
        $stagingMoveExecuted=$true
    }
    $stage='Verify placed synthetic MailItem'
    $problems=New-Object 'System.Collections.Generic.List[string]'
    if([int]$srcFolder.Items.Count -ne 1){[void]$problems.Add('SourceItemsNotOne')}
    if([int]$dstFolder.Items.Count -ne 0){[void]$problems.Add('TargetNotEmpty')}
    if([string]::IsNullOrWhiteSpace([string]$mail.EntryID)){
        [void]$problems.Add('MissingStagedEntryID')
    }
    if(-not (Test-OPA264Live3FolderIdentity `
        -ObservedStoreId ([string]$mail.Parent.StoreID) `
        -ObservedFolderEntryId ([string]$mail.Parent.EntryID) `
        -ExpectedStoreId ([string]$src.StoreID) `
        -ExpectedFolderEntryId ([string]$srcFolder.EntryID))){
        [void]$problems.Add('UnexpectedStagedParentFolder')
    }
    if([string]$mail.Subject -cne $subject){
        [void]$problems.Add('StagedSubjectMismatch')
    }
    $stagedMessageId=[string]$mail.PropertyAccessor.GetProperty(
        'http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if($stagedMessageId -cne $messageId){
        [void]$problems.Add('StagedInternetMessageIdMismatch')
    }
    if($problems.Count -gt 0){
        throw ('LIVE3 placed synthetic mail failed verification: '+($problems.ToArray() -join ', '))
    }
    $stage='Write durable test-only Intent'
    $req=[pscustomobject]@{
        Schema='2.6.4-LIVE3.Request.1'
        RunId=$paths.RunId
        OperationId=$operation
        SourcePst=$paths.SourcePst
        ArchivePst=$paths.ArchivePst
        JournalPath=$paths.JournalPath
        SourceStoreId=[string]$src.StoreID
        ArchiveStoreId=[string]$dst.StoreID
        SourceFolderEntryId=[string]$srcFolder.EntryID
        ArchiveFolderEntryId=[string]$dstFolder.EntryID
        SourceFolderPath=[string]$srcFolder.FolderPath
        ArchiveFolderPath=[string]$dstFolder.FolderPath
        SourceEntryId=[string]$mail.EntryID
    }
    $journal=@{
        Path=$paths.JournalPath;TransactionId=$paths.RunId;OperationId=$operation
        Sequence=1;Phase='Intent';OperationKind='MailMove'
        SourceEntryId=[string]$mail.EntryID;SourceStoreId=[string]$src.StoreID
        SourceFolderPath=[string]$srcFolder.FolderPath
        TargetFolderPath=[string]$dstFolder.FolderPath
        ArchivePst=$paths.ArchivePst;InternetMessageId=$messageId
        Subject=$subject;Sender='';Size=[long]$mail.Size
    }
    [void](Write-OPAOperationJournalEvent @journal)
    Write-OPAWorkerJsonAtomic -Path $paths.RequestPath -Value $req
    $marker=[pscustomobject]@{
        Purpose='OPA264-LIVE3-OneSyntheticMail'
        RunId=$paths.RunId
        SourcePst=$paths.SourcePst
        ArchivePst=$paths.ArchivePst
        SourceFolderName=$paths.SourceFolderName
        ArchiveFolderName=$paths.ArchiveFolderName
        AllowExistingMailMove=$false
    }
    Write-OPAWorkerJsonAtomic -Path $paths.ScopePath -Value $marker
    $stage='Verify durable fixture'
    [void](Assert-OPA264Live3Request -Request $req -BeforeMove)
    [void](Assert-OPA264Live3Intent -Request $req -Paths $paths)
    Write-Output ([pscustomobject]@{
        Status='SyntheticFixturePrepared'
        RunId=$paths.RunId
        OperationId=$operation
        SourcePst=$paths.SourcePst
        SourceFolder=$paths.SourceFolderName
        ArchivePst=$paths.ArchivePst
        RequestFile=$paths.RequestPath
        JournalFile=$paths.JournalPath
        SyntheticMailCount=1
        FixtureStagingMoveExecuted=[bool]$stagingMoveExecuted
        ExistingInboxTouched=$false
        MailMoveExecuted=$false
        WorkerStarted=$false
        NextStep='Run LIVE3 test-only one-shot Move after separate inspection.'
    })
}
catch{
    throw ("LIVE3 fixture stopped at {0}: {1}. Do NOT run Move against incomplete fixture." -f $stage,$_.Exception.Message)
}
finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
