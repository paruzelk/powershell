#requires -Version 5.1
# LIVE3 TEST-ONLY Worker. One synthetic item, one attempt, no retry.
# Does not import or alter production Archive/Resume/Auto Worker allowlist.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [switch]$Execute,
    [switch]$ConfirmSyntheticOnlyMove
)
$ErrorActionPreference='Stop'
if(-not ($Execute -and $ConfirmSyntheticOnlyMove)){
    throw 'LIVE3 Worker requires both -Execute and -ConfirmSyntheticOnlyMove.'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'LIVE3 Worker requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$req=Read-OPAWorkerJson -Path $paths.RequestPath
$paths=Assert-OPA264Live3Request -Request $req -BeforeMove
$intent=Assert-OPA264Live3Intent -Request $req -Paths $paths
$app=$null;$ns=$null;$stage='Outlook preflight';$claimed=$false
try{
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'Existing test Outlook process must already be running.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'LIVE3 Worker refused a different Outlook profile.'
    }
    $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
    if([string]$src.StoreID -cne [string]$req.SourceStoreId -or
       [string]$dst.StoreID -cne [string]$req.ArchiveStoreId -or
       [string]$src.StoreID -ceq [string]$dst.StoreID){
        throw 'LIVE3 Worker StoreID identity mismatch.'
    }
    $stage='Verify synthetic-only folders and item'
    $from=$ns.GetFolderFromID([string]$req.SourceFolderEntryId,[string]$req.SourceStoreId)
    $to=$ns.GetFolderFromID([string]$req.ArchiveFolderEntryId,[string]$req.ArchiveStoreId)
    if($null -eq $from -or $null -eq $to -or
       [string]$from.StoreID -cne [string]$src.StoreID -or
       [string]$to.StoreID -cne [string]$dst.StoreID -or
       [string]$from.FolderPath -cne [string]$req.SourceFolderPath -or
       [string]$to.FolderPath -cne [string]$req.ArchiveFolderPath -or
       [string]$from.Name -cne [string]$paths.SourceFolderName -or
       [string]$to.Name -cne [string]$paths.ArchiveFolderName){
        throw 'LIVE3 synthetic folder identity mismatch.'
    }
    if([int]$from.Items.Count -ne 1 -or [int]$to.Items.Count -ne 0){
        throw 'LIVE3 Worker requires exactly one synthetic source item and empty target.'
    }
    $mail=$ns.GetItemFromID([string]$req.SourceEntryId,[string]$req.SourceStoreId)
    if($null -eq $mail -or [int]$mail.Class -ne 43 -or
       [string]$mail.EntryID -cne [string]$req.SourceEntryId -or
       [string]$mail.Parent.StoreID -cne [string]$req.SourceStoreId -or
       [string]$mail.Parent.FolderPath -cne [string]$req.SourceFolderPath -or
       [string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F') -cne [string]$intent.InternetMessageId -or
       [string]$mail.Subject -cne [string]$intent.Subject -or
       [string]$mail.SenderEmailAddress -ine [string]$intent.Sender -or
       [long]$mail.Size -ne [long]$intent.Size){
        throw 'LIVE3 Worker found a nonmatching synthetic mail fingerprint.'
    }
    $stage='Write one-shot durable claim'
    $file=$null
    try{
        $file=[IO.FileStream]::new($paths.ClaimPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $data=[Text.Encoding]::UTF8.GetBytes(([string]$req.OperationId+[char]10))
        $file.Write($data,0,$data.Length)
        $file.Flush($true)
        $claimed=$true
    }
    finally{if($null -ne $file){$file.Dispose()}}
    $stage='Perform ONE cross-PST MailItem.Move'
    $moved=$mail.Move($to)
    if($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID)){
        throw 'LIVE3 MailItem.Move did not return a destination EntryID.'
    }
    $response=[pscustomobject]@{
        Schema='2.6.4-LIVE3.MoveResponse.1'
        RunId=$paths.RunId
        OperationId=[string]$req.OperationId
        Status='MoveReturnedNeedsReadOnlyReview'
        WorkerProcessId=[int]$PID
        MoveReturned=$true
        JournalCompleted=$false
        AutomaticRetryAllowed=$false
        RequiresIndependentReconciliation=$true
        SyntheticSourceFolderName=$paths.SourceFolderName
        SyntheticArchiveFolderName=$paths.ArchiveFolderName
        DestinationEntryId=[string]$moved.EntryID
    }
    Write-OPAWorkerJsonAtomic -Path $paths.ResponsePath -Value $response
    Write-Output $response
}
catch{
    $errorText=[string]$_.Exception.Message
    if($claimed -and -not [IO.File]::Exists($paths.ResponsePath)){
        try{
            Write-OPAWorkerJsonAtomic -Path $paths.ResponsePath -Value ([pscustomobject]@{
                Schema='2.6.4-LIVE3.MoveResponse.1'
                RunId=$paths.RunId
                OperationId=[string]$req.OperationId
                Status='Indeterminate'
                WorkerProcessId=[int]$PID
                Stage=$stage
                Error=$errorText
                MoveReturned=$false
                JournalCompleted=$false
                AutomaticRetryAllowed=$false
                RequiresIndependentReconciliation=$true
            })
        }catch{}
    }
    throw ("LIVE3 Worker failed at {0}: {1}. Do NOT repeat a claimed Move; inspect the test-only folders." -f $stage,$errorText)
}
finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
