#requires -Version 5.1
# ARCH2c3: policy for a read-only Outlook COM probe of known disposable PST layouts.
# No PST mount/create, Move/Copy/Delete, or production authorizations.
function Get-OPA265ARCH2c3DisposableLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SuiteId,
        [Parameter(Mandatory=$true)][ValidateSet('BW4k7v','BW4k7v2a1')][string]$FixtureKind,
        [Parameter(Mandatory=$true)][string]$LocalAppData
    )
    $g=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$g) -or
       $g -eq [guid]::Empty -or $g.ToString('D') -cne $SuiteId){
        throw 'ARCH2c3 requires canonical nonempty lowercase suite GUID.'
    }
    if(-not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\\') -or
       -not [IO.Directory]::Exists($LocalAppData)){
        throw 'ARCH2c3 requires existing local LOCALAPPDATA.'
    }
    $parent=if($FixtureKind -ceq 'BW4k7v'){
        'OutlookPOP3Archive-BW4k7v-Isolated'
    }else{
        'OutlookPOP3Archive-BW4k7v2a1-ExistingProfile'
    }
    $prefix='OPA265-'+$FixtureKind+'-'+$SuiteId
    $root=[IO.Path]::GetFullPath((Join-Path $LocalAppData $parent))
    $suite=Join-Path $root ('suite-'+$SuiteId)
    $pst=Join-Path $suite ($prefix+'.pst')
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c3.DisposableLayout.1'
        SuiteId=$SuiteId
        FixtureKind=$FixtureKind
        ProfileName='Outlook'
        TestPstPath=$pst
        SuiteDirectory=$suite
        TestFolderName=$prefix
        EligibleForProduction=$false
        WriterPermit=$false
    }
}
function Assert-OPA265ARCH2c3DisposableLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [switch]$RequirePst)
    $expected=Get-OPA265ARCH2c3DisposableLayout -SuiteId ([string]$Layout.SuiteId) -FixtureKind ([string]$Layout.FixtureKind) -LocalAppData $env:LOCALAPPDATA
    foreach($key in @('TestPstPath','SuiteDirectory','TestFolderName','ProfileName')){
        if([string]$Layout.$key -cne [string]$expected.$key){
            throw 'ARCH2c3 disposable path or folder identity mismatch.'
        }
    }
    foreach($path in @([string]$expected.SuiteDirectory, [string]$expected.TestPstPath)){
        if(([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) -and
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH2c3 disposable fixture reparse point forbidden.'
        }
    }
    $parent=[IO.Directory]::GetParent([string]$expected.SuiteDirectory)
    if($null -eq $parent){throw 'ARCH2c3 invalid disposable parent.'}
    if([IO.Directory]::Exists($parent.FullName) -and
       (([IO.File]::GetAttributes($parent.FullName) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2c3 parent reparse point forbidden.'
    }
    if($RequirePst -and -not [IO.File]::Exists($expected.TestPstPath)){
        throw 'ARCH2c3 previously created disposable PST not found; no PST creation authorized.'
    }
    return $true
}
function Test-OPA265ARCH2c3StoreScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Layout,
        [Parameter(Mandatory=$true)][string]$ActualProfileName,
        [Parameter(Mandatory=$true)][string]$DefaultStoreId,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Stores,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Accounts
    )
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if($ActualProfileName -cne [string]$Layout.ProfileName){$issues.Add('WrongProfile')|Out-Null}
    if($Stores.Count -lt 1 -or $Stores.Count -gt 32){$issues.Add('UnboundedStoreInventory')|Out-Null}
    if($Accounts.Count -gt 64){$issues.Add('UnboundedAccountInventory')|Out-Null}
    $matches=@($Stores | Where-Object {
        $p=[string]$_.FilePath
        -not [string]::IsNullOrWhiteSpace($p) -and
        [string]::Equals([IO.Path]::GetFullPath($p),
            [string]$Layout.TestPstPath,[StringComparison]::OrdinalIgnoreCase)
    })
    if($matches.Count -ne 1){$issues.Add('TargetPstNotUniquelyAttached')|Out-Null}
    $targetId=if($matches.Count -eq 1){[string]$matches[0].StoreId}else{''}
    if([string]::IsNullOrWhiteSpace($targetId)){$issues.Add('NoTargetStoreId')|Out-Null}
    if($targetId -and $targetId -ceq $DefaultStoreId){$issues.Add('TargetIsDefaultStore')|Out-Null}
    foreach($account in $Accounts){
        if($targetId -and [string]$account.DeliveryStoreId -ceq $targetId){
            $issues.Add('TargetIsAccountDeliveryStore')|Out-Null
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c3.StoreScope.1'
        Approved=($issues.Count -eq 0)
        ReasonCodes=@($issues.ToArray())
        TargetStoreId=$targetId
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Test-OPA265ARCH2c3AttachmentEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Witnesses,
        [Parameter(Mandatory=$true)][string]$ExpectedPayloadSha256,
        [Parameter(Mandatory=$true)][long]$ExpectedPayloadBytes
    )
    if($ExpectedPayloadSha256 -cnotmatch '^[a-f0-9]{64}$' -or $ExpectedPayloadBytes -lt 0){
        throw 'ARCH2c3 requires independent 64-character lowercase SHA256 and nonnegative payload byte count.'
    }
    $status='CriticalAttachmentEvidenceMismatchNoWriter'
    $match=$false
    if($Witnesses.Count -eq 1 -and
       [int]$Witnesses[0].Index -eq 1 -and
       [int]$Witnesses[0].Type -eq 1 -and
       [string]$Witnesses[0].PayloadSha256 -ceq $ExpectedPayloadSha256 -and
       [long]$Witnesses[0].PayloadByteCount -eq $ExpectedPayloadBytes){
        $status='DisposableAttachmentBytesMatchedIndependentBaseline'
        $match=$true
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c3.AttachmentEvidence.1'
        Status=$status
        CriticalPayloadMatches=$match
        ActualAttachmentCount=$Witnesses.Count
        OriginalMessageMayBeMoved=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265ARCH2c3RestartedOutlook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][int]$OriginalProcessId,
        [Parameter(Mandatory=$true)][long]$OriginalProcessStartUtcTicks,
        [Parameter(Mandatory=$true)][int]$ObservedProcessId,
        [Parameter(Mandatory=$true)][long]$ObservedProcessStartUtcTicks
    )
    if($OriginalProcessId -le 0 -or $ObservedProcessId -le 0 -or
       $OriginalProcessStartUtcTicks -le 0 -or $ObservedProcessStartUtcTicks -le 0 -or
       $OriginalProcessId -eq $ObservedProcessId -or
       $OriginalProcessStartUtcTicks -eq $ObservedProcessStartUtcTicks){
        throw 'ARCH2c3 restarted Outlook process not independently confirmed; no claim.'
    }
    return $true
}
