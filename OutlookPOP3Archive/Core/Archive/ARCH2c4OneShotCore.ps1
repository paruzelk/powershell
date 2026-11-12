#requires -Version 5.1
# ARCH2c4 core integration: one real message from the verified POP3 Inbox to
# a fresh one-shot archive PST. No production Archive/Resume/Auto activation.
. (Join-Path $PSScriptRoot '../Runtime/ComManager.ps1')
. (Join-Path $PSScriptRoot 'ArchiveSelector.ps1')
. (Join-Path $PSScriptRoot 'ARCH2c4OneShotPolicy.ps1')
. (Join-Path $PSScriptRoot 'ARCH2bSemanticWitness.ps1')
function Release-OPA265ARCH2c4Com {
    param([object]$Object)
    if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
    }
}
function Get-OPA265ARCH2c4ItemInInbox {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][string]$SourceStoreId,
          [Parameter(Mandatory=$true)][string]$EntryId)
    if($EntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$'){
        throw 'ARCH2c4 requires the exact original hex Outlook EntryId.'
    }
    $item=$Namespace.GetItemFromID($EntryId,$SourceStoreId)
    $parent=$null
    try {
        if($null -eq $item -or [int]$item.Class -ne 43 -or
           [string]$item.EntryID -cne $EntryId){
            throw 'ARCH2c4 original EntryId not a MailItem.'
        }
        $parent=$item.Parent
        if([string]$parent.EntryID -cne [string]$SourceFolder.EntryID -or
           [string]$parent.StoreID -cne $SourceStoreId){
            throw 'ARCH2c4 candidate no longer belongs to the exact POP3 Inbox.'
        }
        return $item
    }catch {
        Release-OPA265ARCH2c4Com -Object $item
        throw
    }finally {Release-OPA265ARCH2c4Com -Object $parent}
}
function Invoke-OPA265ARCH2c4OneShot {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory','Prepare','Move','Reconcile')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string]$SourceEntryId='',
        [string]$ManifestSha256='',
        [string]$ClaimSha256='',
        [switch]$ConfirmOneShotPreparation,
        [switch]$ConfirmOneShotMove,
        [string]$ApprovalText=''
    )
    $layout=Get-OPA265ARCH2c4Layout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    [void](Assert-OPA265ARCH2c4Layout -Layout $layout)
    $sourcePath=Assert-OPA265ARCH2c4SourcePst -SourcePst $SourcePst -Layout $layout
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2c4.Plan.1'
            Status='ExistingRealPop3OnlyNoOutlookOrFileWrites'
            RunId=$RunId;SourcePst=$sourcePath
            OneShotArchivePst=[string]$layout.ArchivePst
            OneShotArchiveFolder=[string]$layout.ArchiveFolder
            OtherSyntheticPstsRequired=$false
            ModeRequiresLiveOutlook=$false
            ArchiveResumeAutoRemainClosed=$true
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -cin @('Prepare','Move') -and $WhatIfPreference){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2c4.WhatIf.1'
            Status='WhatIfNoOutlookNoPstNoJournalWrites'
            Mode=$Mode;RunId=$RunId
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Prepare'){
        [void](Assert-OPA265ARCH2c4OneShotApproval -Action Prepare -RunId $RunId -ApprovalText $ApprovalText -Confirmed ([bool]$ConfirmOneShotPreparation))
        if($SourceEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$'){
            throw 'ARCH2c4 Prepare needs operator-pinned source EntryId from Inventory.'
        }
    }
    if($Mode -ceq 'Move'){
        [void](Assert-OPA265ARCH2c4OneShotApproval -Action Move -RunId $RunId -ApprovalText $ApprovalText -Confirmed ([bool]$ConfirmOneShotMove))
    }
    if($Mode -cin @('Move','Reconcile')){
        if($ManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'ARCH2c4 Move/Reconcile requires sealed original manifest SHA256.'
        }
    }
    if($Mode -ceq 'Reconcile' -and $ClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2c4 Reconcile requires original immutable move claim SHA256.'
    }
    if($Mode -ceq 'Inventory' -and ($SourceEntryId -or $ManifestSha256 -or $ClaimSha256 -or
       $ConfirmOneShotMove -or $ConfirmOneShotPreparation -or $ApprovalText)){
        throw 'ARCH2c4 Inventory accepts no writer approval or target claim.'
    }
    $app=$null;$ns=$null;$sourceStore=$null;$archiveStore=$null
    $inbox=$null;$archiveRoot=$null;$archiveFolder=$null
    $sourceItem=$null;$moved=$null;$sourceItems=$null;$targetItems=$null
    try {
        $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
        if($procs.Count -ne 1){throw 'ARCH2c4 requires exactly one already running Outlook process.'}
        $proc=$procs[0]
        $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
        # Never create another Outlook process or silently switch profiles.
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        $ns=$app.GetNamespace('MAPI')
        $storeCount=[int]$ns.Stores.Count
        $accountCount=[int]$ns.Accounts.Count
        if($storeCount -lt 1 -or $storeCount -gt 32 -or
           $accountCount -lt 1 -or $accountCount -gt 64){
            throw 'ARCH2c4 unbounded Outlook store/account inventory.'
        }
        $storeRows=New-Object 'System.Collections.Generic.List[object]'
        $accountRows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le $storeCount;$i++){
            $store=$null
            try {
                $store=$ns.Stores.Item($i)
                $file=[string]$store.FilePath
                $storeRows.Add([pscustomobject]@{StoreId=[string]$store.StoreID;FilePath=$file})|Out-Null
                if($file -and [string]::Equals([IO.Path]::GetFullPath($file),
                   $sourcePath,[StringComparison]::OrdinalIgnoreCase)){
                    if($null -ne $sourceStore){throw 'ARCH2c4 duplicate source store.'}
                    $sourceStore=$store;$store=$null
                } elseif($file -and [string]::Equals([IO.Path]::GetFullPath($file),
                   [string]$layout.ArchivePst,[StringComparison]::OrdinalIgnoreCase)){
                    if($null -ne $archiveStore){throw 'ARCH2c4 duplicate target store.'}
                    $archiveStore=$store;$store=$null
                }
            } finally {Release-OPA265ARCH2c4Com -Object $store}
        }
        for($i=1;$i -le $accountCount;$i++){
            $account=$null;$delivery=$null
            try{
                $account=$ns.Accounts.Item($i)
                $delivery=$account.DeliveryStore
                $accountRows.Add([pscustomobject]@{
                    AccountType=[int]$account.AccountType
                    SmtpAddress=[string]$account.SmtpAddress
                    DeliveryStoreId=if($null -eq $delivery){''}else{[string]$delivery.StoreID}
                })|Out-Null
            }finally{
                Release-OPA265ARCH2c4Com -Object $delivery
                Release-OPA265ARCH2c4Com -Object $account
            }
        }
        $default=$null
        try {$default=$ns.DefaultStore;$defaultId=[string]$default.StoreID}
        finally {Release-OPA265ARCH2c4Com -Object $default}
        $scope=Test-OPA265ARCH2c4Pop3StoreScope -Layout $layout -SourcePst $sourcePath -CurrentProfileName ([string]$ns.CurrentProfileName) -DefaultStoreId $defaultId -Stores @($storeRows.ToArray()) -Accounts @($accountRows.ToArray())
        if(-not $scope.Approved -or $null -eq $sourceStore -or
           [string]$sourceStore.StoreID -cne [string]$scope.SourceStoreId){
            throw ('ARCH2c4 POP3 source identity invalid: '+($scope.ReasonCodes -join ','))
        }
        $inbox=$sourceStore.GetDefaultFolder(6)
        if($null -eq $inbox -or [string]$inbox.StoreID -cne [string]$scope.SourceStoreId){
            throw 'ARCH2c4 source is not the verified POP3 Inbox.'
        }
        if($Mode -ceq 'Inventory'){
            $sourceItems=$inbox.Items
            $count=[int]$sourceItems.Count
            if($count -lt 1 -or $count -gt 500000){
                throw 'ARCH2c4 Inbox item count outside bounded inventory.'
            }
            $sourceItems.Sort('[ReceivedTime]',$false)
            $rows=New-Object 'System.Collections.Generic.List[object]'
            for($i=1;$i -le [Math]::Min($count,32) -and $rows.Count -lt 5;$i++){
                $it=$null
                try {
                    $it=$sourceItems.Item($i)
                    if($null -eq $it -or [int]$it.Class -ne 43){continue}
                    $rows.Add([pscustomobject][ordered]@{
                        EntryId=[string]$it.EntryID
                        SubjectSha256=(Get-OPA265ARCH2bTextSha256 -Text ([string]$it.Subject))
                        ReceivedUtc=[datetime]$it.ReceivedTime
                        AttachmentCount=[int]$it.Attachments.Count
                    })|Out-Null
                } finally {Release-OPA265ARCH2c4Com -Object $it}
            }
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.RealPop3Inventory.1'
                Status='ReadOnlyExistingPop3InboxCandidateInventory'
                RunId=$RunId;SourcePst=$sourcePath
                InboxCount=$count;Candidates=@($rows.ToArray())
                OutlookProcessId=[int]$proc.Id;OutlookProcessStartUtcTicks=$ticks
                OriginalPstWrittenByTool=$false
                WriterPermit=$false;ProductionReady=$false
            }
        }
        if($Mode -ceq 'Prepare'){
            if($scope.ArchiveAlreadyAttached -or [IO.Directory]::Exists([string]$layout.RunDirectory) -or
               [IO.File]::Exists([string]$layout.ArchivePst) -or
               [IO.File]::Exists([string]$layout.GlobalClaimPath)){
                throw 'ARCH2c4 run/archive or global one-shot claim already exists; cannot prepare again.'
            }
            $sourceItem=Get-OPA265ARCH2c4ItemInInbox -Namespace $ns -SourceFolder $inbox -SourceStoreId ([string]$scope.SourceStoreId) -EntryId $SourceEntryId
            $witness=Get-OPA265ARCH2bMailSemanticWitness -Mail $sourceItem
            if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $witness)){
                throw 'ARCH2c4 original source witness incomplete; no preparation.'
            }
            if(-not $PSCmdlet.ShouldProcess([string]$layout.ArchivePst,'Create exactly ONE new archive PST for real POP3 one-shot pilot')){
                throw 'ARCH2c4 operator declined fresh archive PST preparation.'
            }
            if(-not [IO.Directory]::Exists([string]$layout.Root)){
                [void][IO.Directory]::CreateDirectory([string]$layout.Root)
            }
            [void][IO.Directory]::CreateDirectory([string]$layout.RunDirectory)
            $intent=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.PrepareIntent.1'
                RunId=$RunId;SourcePst=$sourcePath
                SourceEntryId=$SourceEntryId
                SourceStoreId=[string]$scope.SourceStoreId
                SourceFolderId=[string]$inbox.EntryID
                DestinationPst=[string]$layout.ArchivePst
                OneShotOnly=$true;NeverRetry=$true
            }
            $intentSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.IntentPath -Value $intent
            # If this COM call or any later prepare step fails, intent remains.
            # The same RunId is not retried automatically.
            $ns.AddStoreEx([string]$layout.ArchivePst,2)
            if(-not [IO.File]::Exists([string]$layout.ArchivePst)){
                throw 'ARCH2c4 AddStoreEx did not create new archive PST.'
            }
            $found=0
            for($i=1;$i -le [int]$ns.Stores.Count;$i++){
                $candidate=$null
                try {
                    $candidate=$ns.Stores.Item($i)
                    $path=[string]$candidate.FilePath
                    if($path -and [string]::Equals([IO.Path]::GetFullPath($path),
                        [string]$layout.ArchivePst,[StringComparison]::OrdinalIgnoreCase)){
                        $found++
                        if($found -eq 1){$archiveStore=$candidate;$candidate=$null}
                    }
                }finally {Release-OPA265ARCH2c4Com -Object $candidate}
            }
            if($found -ne 1){throw 'ARCH2c4 created archive store not unique.'}
            $archiveRoot=$archiveStore.GetRootFolder()
            if([int]$archiveRoot.Items.Count -ne 0 -or [int]$archiveRoot.Folders.Count -gt 32){
                throw 'ARCH2c4 fresh archive PST root not empty or unsafe.'
            }
            for($i=1;$i -le [int]$archiveRoot.Folders.Count;$i++){
                $old=$archiveRoot.Folders.Item($i)
                try {if([string]$old.Name -ceq [string]$layout.ArchiveFolder){
                    throw 'ARCH2c4 target folder already exists.'
                }}finally {Release-OPA265ARCH2c4Com -Object $old}
            }
            $archiveFolder=$archiveRoot.Folders.Add([string]$layout.ArchiveFolder)
            if([int]$archiveFolder.Items.Count -ne 0){
                throw 'ARCH2c4 target folder not empty.'
            }
            $manifest=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.PreMoveManifest.1'
                RunId=$RunId;IntentSha256=$intentSha
                SourcePst=$sourcePath
                SourceEntryId=$SourceEntryId
                SourceStoreId=[string]$scope.SourceStoreId
                SourceFolderId=[string]$inbox.EntryID
                DestinationPst=[string]$layout.ArchivePst
                DestinationStoreId=[string]$archiveStore.StoreID
                DestinationFolderId=[string]$archiveFolder.EntryID
                DestinationFolderName=[string]$layout.ArchiveFolder
                SourceSemanticWitness=$witness
                PrepareOutlookProcessId=[int]$proc.Id
                PrepareOutlookProcessStartUtcTicks=$ticks
                AttemptClaimed=$false
                WriterPermit=$false;ProductionReady=$false
            }
            $sha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ManifestPath -Value $manifest
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.Prepared.1'
                Status='FreshRealPop3OneShotArchivePreparedNoMove'
                RunId=$RunId
                ManifestSha256=$sha
                OriginalSourceEntryId=$SourceEntryId
                ArchivePst=[string]$layout.ArchivePst
                OneShotMoveAlreadyAttempted=$false
                WriterPermit=$false;ProductionReady=$false
            }
        }
        # Move and Reconcile always use sealed original evidence.
        $manifest=Read-OPA265ARCH2c4JsonSealed -Path $layout.ManifestPath -ExpectedSha256 $ManifestSha256
        if([string]$manifest.Schema -cne '2.6.5-ARCH2c4.PreMoveManifest.1' -or
           [string]$manifest.RunId -cne $RunId -or
           [string]$manifest.SourcePst -cne $sourcePath -or
           [string]$manifest.SourceStoreId -cne [string]$scope.SourceStoreId -or
           [string]$manifest.SourceFolderId -cne [string]$inbox.EntryID -or
           [string]$manifest.DestinationPst -cne [string]$layout.ArchivePst -or
           [string]$manifest.DestinationFolderName -cne [string]$layout.ArchiveFolder -or
           -not (Test-OPA265ARCH2bWitnessSchema -Witness $manifest.SourceSemanticWitness) -or
           [bool]$manifest.ProductionReady -or [bool]$manifest.WriterPermit){
            throw 'ARCH2c4 original sealed manifest invalid. STOP.'
        }
        $intent=Read-OPA265ARCH2c4JsonSealed -Path $layout.IntentPath -ExpectedSha256 ([string]$manifest.IntentSha256)
        if([string]$intent.Schema -cne '2.6.5-ARCH2c4.PrepareIntent.1' -or
           [string]$intent.RunId -cne $RunId -or
           [string]$intent.SourceEntryId -cne [string]$manifest.SourceEntryId){
            throw 'ARCH2c4 immutable preparation intent mismatch.'
        }
        if($null -eq $archiveStore -or
           [string]$archiveStore.StoreID -cne [string]$manifest.DestinationStoreId -or
           [string]$archiveStore.StoreID -ceq $defaultId){
            throw 'ARCH2c4 target store absent/changed or became default.'
        }
        foreach($account in @($accountRows.ToArray())){
            if([string]$account.DeliveryStoreId -ceq [string]$archiveStore.StoreID){
                throw 'ARCH2c4 target became a mail account delivery store.'
            }
        }
        $archiveRoot=$archiveStore.GetRootFolder()
        if([int]$archiveRoot.Folders.Count -gt 128){throw 'ARCH2c4 target root topology out of bounds.'}
        $folderMatches=0
        for($i=1;$i -le [int]$archiveRoot.Folders.Count;$i++){
            $f=$archiveRoot.Folders.Item($i)
            try {
                if([string]$f.Name -ceq [string]$layout.ArchiveFolder){
                    $folderMatches++
                    if($folderMatches -eq 1){$archiveFolder=$f;$f=$null}
                }
            }finally {Release-OPA265ARCH2c4Com -Object $f}
        }
        if($folderMatches -ne 1 -or
           [string]$archiveFolder.EntryID -cne [string]$manifest.DestinationFolderId -or
           [string]$archiveFolder.StoreID -cne [string]$manifest.DestinationStoreId){
            throw 'ARCH2c4 destination folder identity mismatch.'
        }
        if($Mode -ceq 'Move'){
            if([IO.File]::Exists([string]$layout.GlobalClaimPath) -or
               [IO.File]::Exists([string]$layout.ClaimPath) -or
               [IO.File]::Exists([string]$layout.ReturnPath)){
                throw 'ARCH2c4 one-shot Move already claimed. NEVER retry.'
            }
            if([int]$proc.Id -ne [int]$manifest.PrepareOutlookProcessId -or
               $ticks -ne [long]$manifest.PrepareOutlookProcessStartUtcTicks){
                throw 'ARCH2c4 Outlook restarted after Prepare. Re-approval/manual review needed; no Move.'
            }
            if([int]$archiveFolder.Items.Count -ne 0){
                throw 'ARCH2c4 destination not empty BEFORE the single Move.'
            }
            $sourceItem=Get-OPA265ARCH2c4ItemInInbox -Namespace $ns -SourceFolder $inbox -SourceStoreId ([string]$scope.SourceStoreId) -EntryId ([string]$manifest.SourceEntryId)
            $fresh=Get-OPA265ARCH2bMailSemanticWitness -Mail $sourceItem
            $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $manifest.SourceSemanticWitness -Destination $fresh
            if(-not $cmp.CriticalContentMatches){
                throw 'ARCH2c4 saved real POP3 source changed since preparation; no Move.'
            }
            if(-not $PSCmdlet.ShouldProcess(([string]$manifest.SourceEntryId+' -> '+[string]$layout.ArchivePst),
                'Exactly ONE irreversible Outlook MailItem.Move; never automatic retry')){
                throw 'ARCH2c4 operator declined irreversible one-shot Move.'
            }
            # Global irreversible fence across ALL ARCH2c4 RunIds: even a
            # crash between global claim and per-run claim never grants retry.
            $global=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.GlobalOneShotClaim.1'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                SourcePst=$sourcePath
                SourceEntryId=[string]$manifest.SourceEntryId
                OneAttemptOnly=$true;AnyLaterRunMustStop=$true
            }
            $globalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath -Value $global
            $claim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.OneShotMoveClaim.1'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                GlobalClaimSha256=$globalSha
                SourceEntryId=[string]$manifest.SourceEntryId
                SourceStoreId=[string]$manifest.SourceStoreId
                DestinationStoreId=[string]$manifest.DestinationStoreId
                MoveProcessId=[int]$proc.Id
                MoveProcessStartUtcTicks=$ticks
                ClaimedBeforeComCall=$true
                RetryForbiddenEvenAfterException=$true
                ProductionReady=$false
            }
            $claimSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ClaimPath -Value $claim
            try {$moved=$sourceItem.Move($archiveFolder)}
            catch {
                throw ('ARCH2c4 COM Move INDETERMINATE. Original claim SHA256='+$claimSha+
                    '. No automatic retry. Read-only reconciliation after Outlook restart required. '+$_.Exception.Message)
            }
            if($null -eq $moved){throw 'ARCH2c4 COM Move returned null; outcome indeterminate.'}
            $parent=$null
            try {
                $parent=$moved.Parent
                $observation=[pscustomobject][ordered]@{
                    Schema='2.6.5-ARCH2c4.MoveReturnObservation.1'
                    RunId=$RunId;ClaimSha256=$claimSha
                    MovedEntryId=[string]$moved.EntryID
                    ParentStoreId=[string]$parent.StoreID
                    ParentFolderId=[string]$parent.EntryID
                    IndependentPostRestartReconciliationRequired=$true
                    RetryForbidden=$true
                    ProductionReady=$false
                }
            }finally {Release-OPA265ARCH2c4Com -Object $parent}
            $returnSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ReturnPath -Value $observation
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2c4.LiveMoveReturned.1'
                Status='OneRealPop3MoveReturnedIndependentRestartReviewRequired'
                RunId=$RunId;ClaimSha256=$claimSha;MoveReturnSha256=$returnSha
                ArchivePst=[string]$layout.ArchivePst
                ReturnedDestinationEntryId=[string]$moved.EntryID
                AutomaticallyRetry=$false
                ProductionReady=$false
            }
        }
        # Reconcile NEVER moves, mounts, deletes, saves or appends evidence.
        $claim=Read-OPA265ARCH2c4JsonSealed -Path $layout.ClaimPath -ExpectedSha256 $ClaimSha256
        $global=Read-OPA265ARCH2c4JsonSealed -Path $layout.GlobalClaimPath -ExpectedSha256 ([string]$claim.GlobalClaimSha256)
        if([string]$claim.Schema -cne '2.6.5-ARCH2c4.OneShotMoveClaim.1' -or
           [string]$claim.RunId -cne $RunId -or
           [string]$claim.ManifestSha256 -cne $ManifestSha256 -or
           [string]$claim.SourceEntryId -cne [string]$manifest.SourceEntryId -or
           -not [bool]$claim.ClaimedBeforeComCall -or
           -not [bool]$claim.RetryForbiddenEvenAfterException -or
           [string]$global.RunId -cne $RunId -or
           [string]$global.ManifestSha256 -cne $ManifestSha256){
            throw 'ARCH2c4 claim/global one-shot provenance mismatch.'
        }
        $restarted=([int]$proc.Id -ne [int]$claim.MoveProcessId -and
                    $ticks -ne [long]$claim.MoveProcessStartUtcTicks)
        if(-not $restarted){throw 'ARCH2c4 independent reconciliation requires a NEW Outlook process.'}
        $sourceCount=-1
        $probe=$null
        try {
            $probe=$ns.GetItemFromID([string]$manifest.SourceEntryId,[string]$manifest.SourceStoreId)
            if($null -eq $probe){$sourceCount=0}
            else {
                $sourceParent=$null
                try{
                    $sourceParent=$probe.Parent
                    $sourceCount=if([string]$sourceParent.EntryID -ceq [string]$inbox.EntryID){1}else{-1}
                }finally {Release-OPA265ARCH2c4Com -Object $sourceParent}
            }
        }catch{
            $inner=$_.Exception
            while($null -ne $inner.InnerException){$inner=$inner.InnerException}
            if([int]$inner.HResult -eq -2147221233){$sourceCount=0}
            else {$sourceCount=-1}
        }finally {Release-OPA265ARCH2c4Com -Object $probe}
        $targetItems=$archiveFolder.Items
        $targetCount=[int]$targetItems.Count
        $semanticMatches=$false;$issues=@()
        if($targetCount -eq 1){
            $dest=$null
            try {
                $dest=$targetItems.Item(1)
                if($null -ne $dest -and [int]$dest.Class -eq 43){
                    $destWitness=Get-OPA265ARCH2bMailSemanticWitness -Mail $dest
                    $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $manifest.SourceSemanticWitness -Destination $destWitness
                    $semanticMatches=[bool]$cmp.CriticalContentMatches
                    $issues=@($cmp.IssueCodes)
                }else{$issues=@('DestinationNotMailItem')}
            }catch {$issues=@('DestinationSemanticReadFailed')}
            finally {Release-OPA265ARCH2c4Com -Object $dest}
        }else{$issues=@('TargetItemCountNotOne')}
        $decision=Test-OPA265ARCH2c4Reconciliation -SourceCount $sourceCount -DestinationCount $targetCount -SemanticContentMatches $semanticMatches -RestartConfirmed $restarted
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2c4.RealIndependentReconciliation.1'
            Status=[string]$decision.Status
            RunId=$RunId;ManifestSha256=$ManifestSha256;ClaimSha256=$ClaimSha256
            SourceOriginalEntryIdObservedCount=$sourceCount
            TargetFolderItemCount=$targetCount
            SemanticContentMatches=$semanticMatches
            IssueCodes=$issues
            OutlookRestartConfirmed=$restarted
            OriginalMoveMayBeRetried=$false
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $sourceItem
        Release-OPA265ARCH2c4Com -Object $moved
        Release-OPA265ARCH2c4Com -Object $sourceItems
        Release-OPA265ARCH2c4Com -Object $targetItems
        Release-OPA265ARCH2c4Com -Object $archiveFolder
        Release-OPA265ARCH2c4Com -Object $archiveRoot
        Release-OPA265ARCH2c4Com -Object $inbox
        Release-OPA265ARCH2c4Com -Object $sourceStore
        Release-OPA265ARCH2c4Com -Object $archiveStore
        Release-OPA265ARCH2c4Com -Object $ns
        Release-OPA265ARCH2c4Com -Object $app
    }
}
