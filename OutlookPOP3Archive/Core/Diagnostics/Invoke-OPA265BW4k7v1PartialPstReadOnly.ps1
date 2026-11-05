#requires -Version 5.1
# BW4k7v1: INDEPENDENT READ-ONLY FORENSIC REVIEW of one failed BW4k7v
# partially-created disposable PST. NEVER Resume/Create/Move/Delete/Save/Send.
# Does not require or fabricate an original pre-Move manifest.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [string]$ExpectedProfileName='Outlook',
    [ValidateRange(1,20)][int]$MaxItemsPerFolder=20,
    [switch]$InspectGetItemFromId
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v1 requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7vOutlookFixtureCapture265.ps1')
[void](Assert-OPA265BW4k7vSuiteId -SuiteId $SuiteId)
if($ExpectedProfileName -cne 'Outlook'){throw 'BW4k7v1 expects Outlook profile Outlook.'}
$layout=Get-OPA265BW4k7vLayout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v1.PartialPstReadOnly.1'
        Status='WhatIfNoOutlookOrPstRead'
        SuiteId=$SuiteId;TestPst=[string]$layout.SourcePst
        ManifestWrittenOrReconstructed=$false
        MoveSendDeleteSaveOrCreateCalled=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
# The unsealed partial fixture is deliberately NOT a verified archive source.
# Failure to find it is a blocker, not permission to recreate it.
if(-not [IO.File]::Exists([string]$layout.SourcePst)){
    throw 'BW4k7v1 original NEW disposable PST not found: STOP, do not create.'
}
foreach($p in @($layout.Root,$layout.SuiteDirectory,$layout.SourcePst)){
    if(([IO.File]::GetAttributes([string]$p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7v1 symlink/reparse target refused.'
    }
}
$stage='Locate exact mounted disposable PST'
$app=$null;$ns=$null;$store=$null;$fixtureRoot=$null
try{
    $process=Get-OPA265BW4k7vOutlookProcess
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7v1 unexpected Outlook profile.'
    }
    $defaultId=[string]$ns.DefaultStore.StoreID
    $store=Get-OPA265BW4k7vExactMountedStore -Namespace $ns -Layout $layout
    if([string]$store.StoreID -ceq $defaultId){
        throw 'BW4k7v1 isolated disposable PST unexpectedly default store: STOP.'
    }
    $root=$store.GetRootFolder()
    $hits=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le [int]$root.Folders.Count;$i++){
        $f=$root.Folders.Item($i)
        if([string]$f.Name -ceq [string]$layout.FixtureRootFolderName){
            $hits.Add($f)
        }
    }
    if($hits.Count -ne 1){throw 'BW4k7v1 expected exactly one existing test fixture root; no repair.'}
    $fixtureRoot=$hits[0]
    if([string]$fixtureRoot.StoreID -cne [string]$store.StoreID -or
       [string]$fixtureRoot.Parent.EntryID -cne [string]$root.EntryID){
        throw 'BW4k7v1 fixture root is outside pinned test store.'
    }
    $stage='Bounded, exact synthetic-only folder enumeration'
    $expected=Get-OPA265BW4k7vFixtureExpectations -SuiteId $SuiteId
    $paths=@('\Inbox','\Sent Items','\Projects\Alpha\2022','\Projects\Beta')
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $folders=New-Object 'System.Collections.Generic.List[object]'
    $openAttempts=0;$openOK=0;$openErrors=0;$collectionErrors=0
    foreach($path in $paths){
        $expectedFolderCount=@($expected.FixtureItems | Where-Object {$_.SourceFolderPath -ceq $path}).Count
        $f=$null;$failure=''
        try{
            $f=Get-OPA265BW4k7vExactFolder -FixtureRoot $fixtureRoot -Case (
                [pscustomobject]@{SourceFolderPath=$path})
        }catch{
            $failure=[string]$_.Exception.Message
            $collectionErrors++
        }
        $n=0
        if($null -ne $f){
            try{$n=[int]$f.Items.Count}catch{
                $failure=[string]$_.Exception.Message;$collectionErrors++
            }
        }
        $folders.Add([pscustomobject][ordered]@{
            FolderPath=$path;FolderFound=($null -ne $f)
            ExpectedItems=$expectedFolderCount;ObservedItemCount=$n
            ExactExpectedCount=($null -ne $f -and $n -eq $expectedFolderCount)
            EnumerationError=$failure
        })
        if($null -eq $f -or $failure){continue}
        if($n -gt $MaxItemsPerFolder){
            throw ('BW4k7v1 refuses to enumerate oversized test folder '+$path+
              ', observed '+$n+', bound '+$MaxItemsPerFolder)
        }
        for($i=1;$i -le $n;$i++){
            $item=$null;$id='';$subject='';$cls=$null;$reason=''
            try{
                $item=$f.Items.Item($i)
                $id=[string]$item.EntryID
                $subject=[string]$item.Subject
                $cls=[int]$item.Class
            }catch{
                $reason=[string]$_.Exception.Message
                $collectionErrors++
            }
            $expectedCase=@($expected.FixtureItems | Where-Object {
                (Get-OPA265BW4k7vExpectedSubject -Item $_) -ceq $subject -and
                $_.SourceFolderPath -ceq $path
            })
            $synthetic=($expectedCase.Count -eq 1 -and
              $cls -eq 43 -and $id -cmatch '^[0-9A-Fa-f]{40,512}$')
            $opened=$null;$err='';$hresult=''
            if($InspectGetItemFromId -and $synthetic){
                $openAttempts++
                try{
                    $byId=$ns.GetItemFromID($id,[string]$store.StoreID)
                    if($null -eq $byId -or [string]$byId.EntryID -cne $id -or
                       [string]$byId.Subject -cne $subject){
                        throw 'BW4k7v1 MAPI by-ID returned nonidentical object.'
                    }
                    $opened=$true;$openOK++
                }catch{
                    $opened=$false;$openErrors++
                    $err=[string]$_.Exception.Message
                    $hresult=('0x{0:X8}' -f ([uint32]([int64]$_.Exception.HResult -band 4294967295L)))
                }
            }
            $rows.Add([pscustomobject][ordered]@{
                FolderPath=$path;Index=$i
                ExpectedSyntheticCase=if($synthetic){[string]$expectedCase[0].Name}else{'UnmatchedOrUnreadable'}
                Class=$cls;IsExactSyntheticItem=$synthetic
                EntryIdPresent=($id.Length -gt 0)
                EntryId=$id
                GetItemFromIdAttempted=($InspectGetItemFromId -and $synthetic)
                GetItemFromIdSucceeded=$opened
                OpenErrorHResult=$hresult;OpenError=$err
                CollectionReadError=$reason
                OtherMessageContentRead=$false
            })
        }
    }
    $nrows=@($rows.ToArray());$found=@($nrows | Where-Object {$_.IsExactSyntheticItem})
    $folderStatus=(@($folders.ToArray() | Where-Object {-not $_.ExactExpectedCount}).Count -eq 0)
    $allIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $unique=$true
    foreach($x in $found){if(-not $allIds.Add([string]$x.EntryId)){$unique=$false}}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v1.PartialPstReadOnly.1'
        Status=if($found.Count -eq 8 -and $folderStatus -and $collectionErrors -eq 0 -and
            $openErrors -eq 0){'EightExactSyntheticItemsVisibleButNoSealedManifestNoMovePermit'}
            else{'PartialDisposablePstReadOnlyDiagnosticRequiresManualReview'}
        SuiteId=$SuiteId;TestPst=[string]$layout.SourcePst
        OriginalManifestExists=[IO.File]::Exists([string]$layout.ManifestPath)
        OriginalManifestSha256=if([IO.File]::Exists([string]$layout.ManifestPath)){
            (Get-FileHash -LiteralPath $layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }else{''}
        OutlookProcessId=[int]$process.Pid
        OutlookProcessStartUtcTicks=[long]$process.StartTicks
        PstIsUniqueMountedNonDefault=$true
        ExpectedFixtureCount=8
        FoundExactSyntheticMailCount=$found.Count
        ExactFolderCounts=$folderStatus
        UniqueVisibleSyntheticEntryIds=$unique
        FolderRows=@($folders.ToArray())
        ItemRows=$nrows
        GetItemFromIdAttempts=$openAttempts
        GetItemFromIdSucceeded=$openOK
        GetItemFromIdFailed=$openErrors
        EnumerationsFailed=$collectionErrors
        RawMailBodiesOrAttachmentsRead=$false
        ExistingEvidenceModified=$false
        OriginalManifestCreatedOrModified=$false
        OldPOP3OrOtherPstTouchedByScript=$false
        OutlookMoveSaveSendDeleteOrNewMailExecuted=$false
        AutomaticRetryOfOldSuiteAllowed=$false
        WriterPermit=$false;ProductionReady=$false
        NextAction='Keep failed PST intact; review observed fixture counts and exact by-ID read errors before any new GUID Create'
    }
}catch{
    throw ('BW4k7v1 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
      '. Read-only diagnostic only; never retry BW4k7v Create for old SuiteId.')
}finally{
    foreach($o in @($fixtureRoot,$store,$ns,$app)){
        if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}
