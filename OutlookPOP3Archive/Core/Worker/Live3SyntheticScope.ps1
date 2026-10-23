#requires -Version 5.1
# LIVE3 pure scope. No Outlook COM and no production Worker changes.
function Get-OPA264Live3Paths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst)
    $id=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$id) -or $id -eq [guid]::Empty) {
        throw 'LIVE3 RunId must be a nonempty GUID.'
    }
    if(-not [IO.Path]::IsPathRooted($SourcePst) -or
        $SourcePst.StartsWith('\\',[StringComparison]::Ordinal) -or
        [IO.Path]::GetExtension($SourcePst) -ine '.pst'){
        throw 'LIVE3 requires a local absolute existing POP3 PST path.'
    }
    $source=[IO.Path]::GetFullPath($SourcePst)
    if(-not [IO.File]::Exists($source)) {throw 'LIVE3 selected existing PST is missing.'}
    if(([IO.File]::GetAttributes($source) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'LIVE3 source PST is a reparse point.'
    }
    $compact=$id.ToString('N')
    $directory=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ('OPA264-LIVE3-'+$compact)
    $archive=Join-Path $directory 'Archive.pst'
    if([string]::Equals($archive,$source,[StringComparison]::OrdinalIgnoreCase)){
        throw 'LIVE3 source and archive PSTs cannot be the same file.'
    }
    return [pscustomobject]@{
        RunId=$id.ToString('D')
        Directory=$directory
        SourcePst=$source
        ArchivePst=$archive
        SourceFolderName=('OPA264-LIVE3-'+$compact)
        ArchiveFolderName=('OPA264-LIVE3-Archive-'+$compact)
        ScopePath=(Join-Path $directory 'scope.json')
        JournalPath=(Join-Path $directory 'move.operations.jsonl')
        RequestPath=(Join-Path $directory 'request.json')
        ClaimPath=(Join-Path $directory 'move-attempt.claim')
        ResponsePath=(Join-Path $directory 'response.json')
    }
}
function Assert-OPA264Live3Fresh {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    if([IO.Directory]::Exists([string]$Paths.Directory)){
        throw 'LIVE3 RunId directory already exists; never reuse a run.'
    }
    foreach($p in @($Paths.ArchivePst,$Paths.ScopePath,$Paths.JournalPath,
        $Paths.RequestPath,$Paths.ClaimPath,$Paths.ResponsePath)){
        if(Test-Path -LiteralPath ([string]$p)){
            throw 'LIVE3 run artifacts already exist.'
        }
    }
    return $true
}
function Assert-OPA264Live3Request {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [switch]$BeforeMove)
    foreach($field in @('RunId','OperationId','SourcePst','ArchivePst',
        'JournalPath','SourceStoreId','ArchiveStoreId','SourceFolderEntryId',
        'ArchiveFolderEntryId','SourceFolderPath','ArchiveFolderPath','SourceEntryId')){
        if($Request.PSObject.Properties.Name -cnotcontains $field -or
            [string]::IsNullOrWhiteSpace([string]$Request.$field)){
            throw ('LIVE3 request missing '+$field)
        }
    }
    $op=[guid]::Empty
    if(-not [guid]::TryParse([string]$Request.OperationId,[ref]$op) -or
        $op -eq [guid]::Empty){throw 'LIVE3 OperationId must be a GUID.'}
    $paths=Get-OPA264Live3Paths -RunId ([string]$Request.RunId) -SourcePst ([string]$Request.SourcePst)
    foreach($name in @('ArchivePst','JournalPath')){
        if(-not [string]::Equals([string]$Request.$name,[string]$paths.$name,
            [StringComparison]::OrdinalIgnoreCase)){
            throw ('LIVE3 request path outside exact scope: '+$name)
        }
    }
    foreach($name in @('Directory','ArchivePst','ScopePath','JournalPath')){
        $p=[string]$paths.$name
        if(-not (Test-Path -LiteralPath $p)){throw ('LIVE3 required file/dir missing: '+$name)}
        if(((Get-Item -LiteralPath $p -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw ('LIVE3 reparse-point scope rejected: '+$name)
        }
    }
    if(-not ([string]$Request.SourceFolderPath).EndsWith(('\'+$paths.SourceFolderName),
        [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$Request.ArchiveFolderPath).EndsWith(('\'+$paths.ArchiveFolderName),
        [StringComparison]::OrdinalIgnoreCase)){
        throw 'LIVE3 request must use exact synthetic source/archive folders.'
    }
    if([string]$Request.SourceStoreId -ceq [string]$Request.ArchiveStoreId){
        throw 'LIVE3 source and archive StoreID cannot match.'
    }
    $scope=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.ScopePath)) -ErrorAction Stop
    if([string]$scope.Purpose -cne 'OPA264-LIVE3-OneSyntheticMail' -or
        [string]$scope.RunId -cne [string]$paths.RunId -or
        [string]$scope.SourcePst -cne [string]$paths.SourcePst -or
        [string]$scope.ArchivePst -cne [string]$paths.ArchivePst -or
        [string]$scope.SourceFolderName -cne [string]$paths.SourceFolderName -or
        [string]$scope.ArchiveFolderName -cne [string]$paths.ArchiveFolderName -or
        [bool]$scope.AllowExistingMailMove){
        throw 'LIVE3 scope marker mismatch.'
    }
    if($BeforeMove -and ([IO.File]::Exists($paths.ClaimPath) -or
        [IO.File]::Exists($paths.ResponsePath))){
        throw 'LIVE3 Move was already claimed or has a response.'
    }
    return $paths
}
function Assert-OPA264Live3Intent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths)
    if(-not (Get-Command Read-OPAOperationJournal -ErrorAction SilentlyContinue)){
        . (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
    }
    $journal=Read-OPAOperationJournal -Path ([string]$Paths.JournalPath)
    if([bool]$journal.TrailingPartial -or @($journal.Events).Count -ne 1){
        throw 'LIVE3 requires exactly one complete durable Intent.'
    }
    $item=$journal.Events[0]
    if([string]$item.Phase -cne 'Intent' -or
        [string]$item.OperationKind -cne 'MailMove' -or
        [string]$item.TransactionId -cne [string]$Paths.RunId -or
        [string]$item.OperationId -cne [string]$Request.OperationId -or
        [string]$item.SourceEntryId -cne [string]$Request.SourceEntryId -or
        [string]$item.SourceStoreId -cne [string]$Request.SourceStoreId -or
        [string]$item.SourceFolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$item.TargetFolderPath -cne [string]$Request.ArchiveFolderPath -or
        [string]$item.ArchivePst -cne [string]$Paths.ArchivePst -or
        [string]::IsNullOrWhiteSpace([string]$item.InternetMessageId) -or
        [string]::IsNullOrWhiteSpace([string]$item.Subject) -or
        [string]::IsNullOrWhiteSpace([string]$item.Sender) -or
        [long]$item.Size -le 0){
        throw 'LIVE3 durable Intent differs from synthetic request.'
    }
    return $item
}
function Get-OPA264Live3MountedStore {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][string]$Path)
    $count=0;$matched=$null
    for($i=1;$i -le [int]$Namespace.Stores.Count;$i++){
        $s=$Namespace.Stores.Item($i)
        $p=''
        try{$p=[string]$s.FilePath}catch{continue}
        if([string]::Equals($p,$Path,[StringComparison]::OrdinalIgnoreCase)){
            $count++;$matched=$s
        }
    }
    if($count -ne 1){throw 'LIVE3 PST is not uniquely mounted in Outlook.'}
    return $matched
}
function Assert-OPA264Live3Pop3Source {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$Store)
    $matched=0
    for($i=1;$i -le [int]$Namespace.Accounts.Count;$i++){
        $a=$Namespace.Accounts.Item($i)
        if([int]$a.AccountType -ne 2){continue}
        $delivery=$a.DeliveryStore
        if($null -ne $delivery -and
            [string]$delivery.StoreID -ceq [string]$Store.StoreID){$matched++}
    }
    if($matched -ne 1){throw 'LIVE3 source must be uniquely bound to POP3 DeliveryStore.'}
    return $true
}
