#requires -Version 5.1
# LIVE3 independent read-only inspection of the exact synthetic folder pair.
# May run BEFORE or AFTER the one-shot diagnostic Worker, never replays Move.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if(-not $Review){throw 'LIVE3 read-only probe requires -Review.'}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'LIVE3 read-only probe requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if(-not [string]::Equals([string]$request.SourcePst,[string]$paths.SourcePst,
    [StringComparison]::OrdinalIgnoreCase)){throw 'LIVE3 request differs from explicitly selected POP3 PST.'}
$paths=Assert-OPA264Live3Request -Request $request
$intent=Assert-OPA264Live3Intent -Request $request -Paths $paths
$app=$null;$ns=$null
try{
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'Already-running test Outlook is required.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'LIVE3 read-only probe refused a different Outlook profile.'
    }
    $sourceStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    $archiveStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $sourceStore)
    if([string]$sourceStore.StoreID -cne [string]$request.SourceStoreId -or
       [string]$archiveStore.StoreID -cne [string]$request.ArchiveStoreId){
        throw 'LIVE3 read-only probe StoreID mismatch.'
    }
    $sourceFolder=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
    $archiveFolder=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
    if($null -eq $sourceFolder -or $null -eq $archiveFolder -or
        [string]$sourceFolder.FolderPath -cne [string]$request.SourceFolderPath -or
        [string]$archiveFolder.FolderPath -cne [string]$request.ArchiveFolderPath){
        throw 'LIVE3 read-only folder identity mismatch.'
    }
    $srcN=[int]$sourceFolder.Items.Count
    $dstN=[int]$archiveFolder.Items.Count
    $srcMatches=0;$dstMatches=0
    foreach($role in @('Source','Destination')){
        $folder=$sourceFolder
        if($role -ceq 'Destination'){$folder=$archiveFolder}
        for($i=1;$i -le [int]$folder.Items.Count;$i++){
            $item=$folder.Items.Item($i)
            if($null -eq $item -or [int]$item.Class -ne 43){continue}
            $msgid=''
            try {
                $msgid=[string]$item.PropertyAccessor.GetProperty(
                    'http://schemas.microsoft.com/mapi/proptag/0x1035001F')
            }catch{continue}
            if($msgid -cne [string]$intent.InternetMessageId -or
                [string]$item.Subject -cne [string]$intent.Subject){continue}
            if($role -ceq 'Source'){$srcMatches++}
            else{$dstMatches++}
        }
    }
    $claimed=[IO.File]::Exists($paths.ClaimPath)
    $responsePresent=[IO.File]::Exists($paths.ResponsePath)
    $status='Indeterminate'
    if($srcN -eq 1 -and $dstN -eq 0 -and $srcMatches -eq 1 -and
       $dstMatches -eq 0 -and -not $claimed -and -not $responsePresent){
        $status='SyntheticReadyForOneShotMove'
    }
    elseif($srcN -eq 0 -and $dstN -eq 1 -and $srcMatches -eq 0 -and
        $dstMatches -eq 1 -and $claimed){
        $status='SyntheticMoveObserved'
    }
    Write-Output ([pscustomobject]@{
        Schema='2.6.4-LIVE3.ReadOnlySnapshot.1'
        RunId=$paths.RunId
        Status=$status
        SourceFolder=$paths.SourceFolderName
        ArchiveFolder=$paths.ArchiveFolderName
        SourceItemCount=$srcN
        ArchiveItemCount=$dstN
        SyntheticSourceMatches=$srcMatches
        SyntheticArchiveMatches=$dstMatches
        AttemptClaimExists=$claimed
        WorkerResponseExists=$responsePresent
        ExistingInboxExamined=$false
        MailMoveExecuted=$false
        JournalCompleted=$false
        ProductionReady=$false
    })
}
finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
