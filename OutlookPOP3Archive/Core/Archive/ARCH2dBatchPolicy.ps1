#requires -Version 5.1
# ARCH2d: real Inbox bounded TEN mail pilot. Pure scope, selection, immutable
# one-way claim and independent comparison policy. No COM or PST side effects.
. (Join-Path $PSScriptRoot 'ARCH2c4OneShotCore.ps1')

function Get-OPA265ARCH2dLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId){
        throw 'ARCH2d requires canonical lowercase RunId GUID.'
    }
    $local=[IO.Path]::GetFullPath($LocalAppData)
    if(-not [IO.Directory]::Exists($local) -or $local.StartsWith('\\') -or
       (([IO.File]::GetAttributes($local) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2d requires existing local non-reparse APPDATA.'
    }
    $root=Join-Path $local 'OutlookPOP3Archive-ARCH2d-RealBatch10'
    $dir=Join-Path $root ('run-'+$RunId)
    $base='OPA265-ARCH2d-'+$RunId
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d.Layout.1'
        RunId=$RunId
        Root=$root
        RunDirectory=$dir
        ArchivePst=Join-Path $dir ($base+'.pst')
        ArchiveFolder=$base
        IntentPath=Join-Path $dir 'prepare-intent.json'
        ManifestPath=Join-Path $dir 'pre-move-manifest.json'
        GlobalClaimPath=Join-Path $root 'ARCH2d-BATCH-ONCE-CLAIM.json'
        AccountEmail='info@stios.ru'
        ProfileName='Outlook'
        BatchSize=10
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Assert-OPA265ARCH2dLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    $expected=Get-OPA265ARCH2dLayout -RunId ([string]$Layout.RunId) -LocalAppData $env:LOCALAPPDATA
    foreach($name in @('Root','RunDirectory','ArchivePst','ArchiveFolder',
        'IntentPath','ManifestPath','GlobalClaimPath','AccountEmail','ProfileName')){
        if([string]$Layout.$name -cne [string]$expected.$name){
            throw ('ARCH2d forged layout field: '+$name)
        }
    }
    foreach($path in @($Layout.Root,$Layout.RunDirectory,$Layout.ArchivePst,
        $Layout.IntentPath,$Layout.ManifestPath,$Layout.GlobalClaimPath)){
        if(([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) -and
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH2d reparse artifact forbidden.'
        }
    }
    if([int]$Layout.BatchSize -ne 10){throw 'ARCH2d batch is exactly 10.'}
    return $true
}

function Get-OPA265ARCH2dItemClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][ValidateRange(1,10)][int]$Ordinal,
          [ValidateSet('Claim','Return')][string]$Kind='Claim')
    $name=('move-{0:D2}-{1}.json' -f $Ordinal,$Kind.ToLowerInvariant())
    return Join-Path ([string]$Layout.RunDirectory) $name
}

function Assert-OPA265ARCH2dEntryIds {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$EntryIds,
          [int]$BatchSize=10)
    if($BatchSize -ne 10 -or @($EntryIds).Count -ne 10){
        throw 'ARCH2d pilot requires EXACTLY 10 operator-pinned source EntryIds.'
    }
    $unique=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($id in $EntryIds){
        if([string]::IsNullOrWhiteSpace($id) -or
           $id -cnotmatch '^[0-9A-Fa-f]{16,1024}$' -or
           -not $unique.Add($id)){
            throw 'ARCH2d duplicate or malformed operator-selected source EntryId.'
        }
    }
    return $true
}

function Get-OPA265ARCH2dSemanticSignature {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $Witness)){
        throw 'ARCH2d incomplete semantic witness.'
    }
    # Stable content selector for comparing destination MailItems without
    # trusting provider EntryIDs to survive a cross-PST move. Do NOT treat
    # signature equality as full verification: compare every witness field.
    return (([string]$Witness.InternetMessageIdSha256)+'|'+
        ([string]$Witness.SubjectSha256)+'|'+
        ([string]$Witness.SenderSha256)+'|'+
        ([string]$Witness.ReceivedUtcTicks))
}

function Assert-OPA265ARCH2dManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$SourceStoreId,
          [Parameter(Mandatory=$true)][string]$SourceFolderId)
    if([string]$Manifest.Schema -cne '2.6.5-ARCH2d.PreMoveManifest.1' -or
       [string]$Manifest.RunId -cne [string]$Layout.RunId -or
       [string]$Manifest.SourcePst -cne $SourcePst -or
       [string]$Manifest.ArchivePst -cne [string]$Layout.ArchivePst -or
       [string]$Manifest.ArchiveFolder -cne [string]$Layout.ArchiveFolder -or
       [string]$Manifest.SourceStoreId -cne $SourceStoreId -or
       [string]$Manifest.SourceFolderId -cne $SourceFolderId -or
       [string]$Manifest.ArchiveStoreId -ceq $SourceStoreId -or
       [int]$Manifest.BatchSize -ne 10 -or
       [bool]$Manifest.ProductionReady -or
       [bool]$Manifest.WriterPermit -or
       [string]$Manifest.IntentSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d manifest identity, source scope or field schema mismatch.'
    }
    $items=@($Manifest.Items)
    if($items.Count -ne 10){throw 'ARCH2d sealed manifest does not contain exactly ten items.'}
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sigs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for($i=0;$i -lt 10;$i++){
        $row=$items[$i]
        if($null -eq $row -or [int]$row.Ordinal -ne ($i+1) -or
           [string]$row.SourceEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
           -not $ids.Add([string]$row.SourceEntryId) -or
           -not (Test-OPA265ARCH2bWitnessSchema -Witness $row.SourceSemanticWitness)){
            throw 'ARCH2d manifest item ordinal, EntryId or witness invalid.'
        }
        $signature=Get-OPA265ARCH2dSemanticSignature -Witness $row.SourceSemanticWitness
        if([string]$row.SemanticSignature -cne $signature -or
           -not $sigs.Add($signature)){
            throw 'ARCH2d duplicate or mismatched semantic selector; batch ambiguous.'
        }
    }
    return $true
}

function Assert-OPA265ARCH2dApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Prepare','MoveBatch')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][bool]$Confirmed,
          [Parameter(Mandatory=$true)][string]$ApprovalText)
    $expected=$Mode.ToUpperInvariant()+' ARCH2D '+$RunId
    if(-not $Confirmed -or $ApprovalText -cne $expected){
        throw ('ARCH2d explicit irreversible one-batch approval required: '+$expected)
    }
    return $true
}

function Get-OPA265ARCH2dSourcePresence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][string]$EntryId,
          [Parameter(Mandatory=$true)][string]$StoreId,
          [Parameter(Mandatory=$true)][string]$FolderId)
    $item=$null
    $parent=$null
    try {
        $item=$Namespace.GetItemFromID($EntryId,$StoreId)
        if($null -eq $item){return -1}
        $parent=$item.Parent
        if([string]$parent.StoreID -cne $StoreId){return -1}
        if([string]$parent.EntryID -cne $FolderId){return -1}
        return 1
    }
    catch {
        $err=$_.Exception
        while($null -ne $err.InnerException){$err=$err.InnerException}
        # 0x8004010F = MAPI_E_NOT_FOUND: original EntryId no longer exists.
        # Anything else is UNKNOWN, never interpreted as absence.
        if([int]$err.HResult -eq -2147221233){return 0}
        return -1
    }
    finally {
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $item
    }
}

function Get-OPA265ARCH2dReconcileDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ItemResults,
          [Parameter(Mandatory=$true)][int]$DestinationItemCount,
          [Parameter(Mandatory=$true)][bool]$RestartConfirmed)
    if(@($ItemResults).Count -ne 10){throw 'ARCH2d reconciliation requires exactly 10 planned items.'}
    $verified=@($ItemResults | Where-Object { [string]$_.Status -ceq 'MovedAndSemanticallyMatched' }).Count
    $untouched=@($ItemResults | Where-Object { [string]$_.Status -ceq 'NotAttemptedOriginalSourcePresent' }).Count
    $claimed=@($ItemResults | Where-Object { [bool]$_.MoveClaimExists }).Count
    $ok=$RestartConfirmed -and $verified -eq 10 -and $claimed -eq 10 -and
        $DestinationItemCount -eq 10
    $validPartial=$RestartConfirmed -and $verified+$untouched -eq 10 -and
        $DestinationItemCount -eq $verified -and $claimed -eq $verified
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d.ReconciliationDecision.1'
        Status=if($ok){'AllTenIndependentPostRestartSemanticMatches'}elseif($validPartial){
            'PartialBatchVerifiedButNoResumePermit'
        }else{'ManualReviewRequiredNoAutomaticRetry'}
        VerifiedMoved=$verified
        NotAttempted=$untouched
        Claimed=$claimed
        Planned=10
        DestinationItemCount=$DestinationItemCount
        IndependentlyVerifiedAllTen=$ok
        AutomaticRetryAllowed=$false
        ArchiveResumeAutoRemainClosed=$true
        ProductionReady=$false
    }
}
