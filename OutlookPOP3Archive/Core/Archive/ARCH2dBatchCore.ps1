#requires -Version 5.1
# ARCH2d: ONE explicit batch of exactly ten existing POP3 Inbox MailItems.
# NO global Archive/Resume/Auto enabled. No blind retry after any claim.
. (Join-Path $PSScriptRoot 'ARCH2dBatchPolicy.ps1')

function Open-OPA265ARCH2dSession {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SourcePst)
    $app=$null;$ns=$null;$src=$null;$dst=$null;$inbox=$null
    try {
        $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
        if($processes.Count -ne 1){throw 'ARCH2d requires exactly one running Outlook process.'}
        $proc=$processes[0]
        if([int]$proc.SessionId -ne [int](Get-Process -Id $PID).SessionId){
            throw 'ARCH2d Outlook and PowerShell Windows sessions differ.'
        }
        # Attach only to the existing authenticated Outlook instance.
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        $ns=$app.GetNamespace('MAPI')
        $stores=New-Object 'System.Collections.Generic.List[object]'
        $accounts=New-Object 'System.Collections.Generic.List[object]'
        $sc=[int]$ns.Stores.Count;$ac=[int]$ns.Accounts.Count
        if($sc -lt 1 -or $sc -gt 32 -or $ac -lt 1 -or $ac -gt 64){
            throw 'ARCH2d store/account topology unbounded.'
        }
        for($i=1;$i -le $sc;$i++){
            $s=$null
            try {
                $s=$ns.Stores.Item($i)
                $fp=[string]$s.FilePath
                $id=[string]$s.StoreID
                $stores.Add([pscustomobject]@{StoreId=$id;FilePath=$fp})|Out-Null
                if($fp){
                    $full=[IO.Path]::GetFullPath($fp)
                    if([string]::Equals($full,$SourcePst,[StringComparison]::OrdinalIgnoreCase)){
                        if($null -ne $src){throw 'ARCH2d multiple source stores.'}
                        $src=$s;$s=$null
                    }elseif([string]::Equals($full,[string]$Layout.ArchivePst,
                        [StringComparison]::OrdinalIgnoreCase)){
                        if($null -ne $dst){throw 'ARCH2d multiple archive stores.'}
                        $dst=$s;$s=$null
                    }
                }
            }finally {Release-OPA265ARCH2c4Com -Object $s}
        }
        for($i=1;$i -le $ac;$i++){
            $a=$null;$delivery=$null
            try {
                $a=$ns.Accounts.Item($i)
                $delivery=$a.DeliveryStore
                $accounts.Add([pscustomobject]@{
                    SmtpAddress=[string]$a.SmtpAddress
                    AccountType=[int]$a.AccountType
                    DeliveryStoreId=if($null -eq $delivery){''}else{[string]$delivery.StoreID}
                })|Out-Null
            }finally{
                Release-OPA265ARCH2c4Com -Object $delivery
                Release-OPA265ARCH2c4Com -Object $a
            }
        }
        $default=$null
        try {
            $default=$ns.DefaultStore
            $defaultId=[string]$default.StoreID
        }finally{Release-OPA265ARCH2c4Com -Object $default}
        $scope=Test-OPA265ARCH2c4Pop3StoreScope -Layout $Layout -SourcePst $SourcePst -CurrentProfileName ([string]$ns.CurrentProfileName) -DefaultStoreId $defaultId -Stores @($stores.ToArray()) -Accounts @($accounts.ToArray())
        if(-not [bool]$scope.Approved -or $null -eq $src -or
           [string]$scope.SourceStoreId -cne [string]$src.StoreID){
            throw ('ARCH2d original POP3 source not verified: '+($scope.ReasonCodes -join ','))
        }
        $inbox=$src.GetDefaultFolder(6)
        if($null -eq $inbox -or [string]$inbox.StoreID -cne [string]$scope.SourceStoreId){
            throw 'ARCH2d exact source is not original POP3 Inbox.'
        }
        $result=[pscustomobject][ordered]@{
            App=$app;Namespace=$ns;SourceStore=$src;ArchiveStore=$dst
            Inbox=$inbox;Scope=$scope;Accounts=@($accounts.ToArray())
            DefaultStoreId=$defaultId
            OutlookProcessId=[int]$proc.Id
            OutlookProcessStartUtcTicks=[int64]$proc.StartTime.ToUniversalTime().Ticks
        }
        return $result
    }catch{
        Release-OPA265ARCH2c4Com -Object $inbox
        Release-OPA265ARCH2c4Com -Object $dst
        Release-OPA265ARCH2c4Com -Object $src
        Release-OPA265ARCH2c4Com -Object $ns
        Release-OPA265ARCH2c4Com -Object $app
        throw
    }
}

function Close-OPA265ARCH2dSession {
    param([object]$Session)
    if($null -eq $Session){return}
    Release-OPA265ARCH2c4Com -Object $Session.Inbox
    Release-OPA265ARCH2c4Com -Object $Session.ArchiveStore
    Release-OPA265ARCH2c4Com -Object $Session.SourceStore
    Release-OPA265ARCH2c4Com -Object $Session.Namespace
    Release-OPA265ARCH2c4Com -Object $Session.App
}

function Get-OPA265ARCH2dTargetFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session,
          [Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][object]$Manifest)
    if($null -eq $Session.ArchiveStore -or
       [string]$Session.ArchiveStore.StoreID -cne [string]$Manifest.ArchiveStoreId -or
       [string]$Session.ArchiveStore.StoreID -ceq [string]$Session.DefaultStoreId){
        throw 'ARCH2d archive store missing/changed or became default.'
    }
    foreach($a in @($Session.Accounts)){
        if([string]$a.DeliveryStoreId -ceq [string]$Session.ArchiveStore.StoreID){
            throw 'ARCH2d archive became an email-account delivery store.'
        }
    }
    $root=$null;$found=$null
    try{
        $root=$Session.ArchiveStore.GetRootFolder()
        $folders=$root.Folders
        $fc=[int]$folders.Count
        if($fc -lt 1 -or $fc -gt 128){throw 'ARCH2d archive root topology out of bounds.'}
        $matches=0
        for($i=1;$i -le $fc;$i++){
            $f=$null
            try{
                $f=$folders.Item($i)
                if([string]$f.Name -ceq [string]$Layout.ArchiveFolder){
                    $matches++
                    if($matches -eq 1){$found=$f;$f=$null}
                }
            }finally{Release-OPA265ARCH2c4Com -Object $f}
        }
        if($matches -ne 1 -or $null -eq $found -or
           [string]$found.EntryID -cne [string]$Manifest.ArchiveFolderId -or
           [string]$found.StoreID -cne [string]$Manifest.ArchiveStoreId){
            throw 'ARCH2d archive folder identity mismatch.'
        }
        $out=$found;$found=$null
        return $out
    }finally{
        Release-OPA265ARCH2c4Com -Object $found
        Release-OPA265ARCH2c4Com -Object $root
    }
}

function Invoke-OPA265ARCH2dBatch {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory','Prepare','MoveBatch','Reconcile')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string[]]$SourceEntryIds=@(),
        [string]$ManifestSha256='',
        [string]$BatchClaimSha256='',
        [switch]$ConfirmBatchPreparation,
        [switch]$ConfirmBatchMove,
        [string]$ApprovalText=''
    )
    $layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    [void](Assert-OPA265ARCH2dLayout -Layout $layout)
    $source=Assert-OPA265ARCH2c4SourcePst -SourcePst $SourcePst -Layout $layout
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.Plan.1'
            Status='BoundedTenRealPop3SourcePlanNoOutlookNoWrites'
            RunId=$RunId;SourcePst=$source
            DestinationPst=[string]$layout.ArchivePst
            BatchSize=10;PreviousARCH2c4RunUntouched=$true
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }
    if($Mode -cin @('Prepare','MoveBatch') -and $WhatIfPreference){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.WhatIf.1'
            Mode=$Mode
            Status='WhatIfNoOutlookNoPstNoJournalWrites'
            RunId=$RunId;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Prepare'){
        [void](Assert-OPA265ARCH2dEntryIds -EntryIds $SourceEntryIds)
        [void](Assert-OPA265ARCH2dApproval -Mode Prepare -RunId $RunId -Confirmed ([bool]$ConfirmBatchPreparation) -ApprovalText $ApprovalText)
    }elseif($Mode -ceq 'MoveBatch'){
        [void](Assert-OPA265ARCH2dApproval -Mode MoveBatch -RunId $RunId -Confirmed ([bool]$ConfirmBatchMove) -ApprovalText $ApprovalText)
    }
    if($Mode -cin @('MoveBatch','Reconcile') -and
       $ManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d exact sealed original ManifestSha256 required.'
    }
    if($Mode -ceq 'Reconcile' -and $BatchClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d independent review requires exact original BatchClaimSha256.'
    }
    if($Mode -ceq 'Inventory' -and (@($SourceEntryIds).Count -ne 0 -or
       $ManifestSha256 -or $BatchClaimSha256 -or $ApprovalText -or
       $ConfirmBatchPreparation -or $ConfirmBatchMove)){
        throw 'ARCH2d Inventory is read-only and takes no writer arguments.'
    }

    $session=$null;$items=$null;$root=$null;$target=$null;$moved=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if($Mode -ceq 'Inventory'){
            $items=$session.Inbox.Items
            $n=[int]$items.Count
            if($n -lt 10 -or $n -gt 500000){throw 'ARCH2d Inbox count outside minimum or bounded inventory.'}
            $items.Sort('[ReceivedTime]',$false)
            $rows=New-Object 'System.Collections.Generic.List[object]'
            for($i=1;$i -le [Math]::Min($n,128) -and $rows.Count -lt 16;$i++){
                $mail=$null
                try {
                    $mail=$items.Item($i)
                    if($null -eq $mail -or [int]$mail.Class -ne 43){continue}
                    $rows.Add([pscustomobject][ordered]@{
                        EntryId=[string]$mail.EntryID
                        SubjectSha256=(Get-OPA265ARCH2bTextSha256 -Text ([string]$mail.Subject))
                        ReceivedUtc=[datetime]$mail.ReceivedTime
                        AttachmentCount=[int]$mail.Attachments.Count
                    })|Out-Null
                }finally{Release-OPA265ARCH2c4Com -Object $mail}
            }
            if($rows.Count -lt 10){throw 'ARCH2d fewer than 10 eligible MailItems in bounded scan.'}
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.RealInboxInventory.1'
                Status='ReadOnlyTenCandidatePop3InboxInventory'
                RunId=$RunId
                InboxCount=$n
                Candidates=@($rows.ToArray())
                BatchSize=10
                OutlookProcessId=[int]$session.OutlookProcessId
                OutlookProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                ProductionReady=$false
            }
        }
        if($Mode -ceq 'Prepare'){
            if([IO.Directory]::Exists([string]$layout.RunDirectory) -or
               [IO.File]::Exists([string]$layout.GlobalClaimPath) -or
               [IO.File]::Exists([string]$layout.ArchivePst) -or
               $null -ne $session.ArchiveStore){
                throw 'ARCH2d run directory/archive/global claim already exists. No automatic Prepare retry.'
            }
            # Before any new directory/PST, capture EVERY source letter and hash
            # its actual Body/HTML/recipients/state/by-value attachment bytes.
            $rows=New-Object 'System.Collections.Generic.List[object]'
            $signatures=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            for($i=0;$i -lt 10;$i++){
                $mail=$null
                try{
                    $mail=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$session.SourceStore.StoreID) -EntryId ([string]$SourceEntryIds[$i])
                    $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                    $sig=Get-OPA265ARCH2dSemanticSignature -Witness $w
                    if(-not $signatures.Add($sig)){
                        throw 'ARCH2d semantic selector collision among source letters: change selection, no archive created.'
                    }
                    $rows.Add([pscustomobject][ordered]@{
                        Ordinal=[int]($i+1)
                        SourceEntryId=[string]$SourceEntryIds[$i]
                        SemanticSignature=$sig
                        SourceSemanticWitness=$w
                    })|Out-Null
                }finally{Release-OPA265ARCH2c4Com -Object $mail}
            }
            if(-not $PSCmdlet.ShouldProcess([string]$layout.ArchivePst,'Create ONE new isolated archive PST to receive EXACTLY TEN real POP3 Inbox messages')){
                throw 'ARCH2d operator declined target archive preparation.'
            }
            if(-not [IO.Directory]::Exists([string]$layout.Root)){
                [void][IO.Directory]::CreateDirectory([string]$layout.Root)
            }
            [void][IO.Directory]::CreateDirectory([string]$layout.RunDirectory)
            $intent=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.PrepareIntent.1'
                RunId=$RunId;SourcePst=$source
                SourceStoreId=[string]$session.SourceStore.StoreID
                SourceFolderId=[string]$session.Inbox.EntryID
                DestinationPst=[string]$layout.ArchivePst
                PlannedCount=10
                SourceEntryIds=@($rows.ToArray()|ForEach-Object{[string]$_.SourceEntryId})
                NewTargetOnly=$true;AutomaticPrepareRetryAllowed=$false
            }
            $intentSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.IntentPath -Value $intent
            # COM AddStoreEx can create PST, so the original PrepareIntent has
            # already been force-flushed. Never retry a partially created run.
            $session.Namespace.AddStoreEx([string]$layout.ArchivePst,2)
            if(-not [IO.File]::Exists([string]$layout.ArchivePst)){
                throw 'ARCH2d provider did not create target PST.'
            }
            $found=0
            for($i=1;$i -le [int]$session.Namespace.Stores.Count;$i++){
                $s=$null
                try{
                    $s=$session.Namespace.Stores.Item($i)
                    $fp=[string]$s.FilePath
                    if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),
                        [string]$layout.ArchivePst,[StringComparison]::OrdinalIgnoreCase)){
                        $found++
                        if($found -eq 1){$session.ArchiveStore=$s;$s=$null}
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $s}
            }
            if($found -ne 1){throw 'ARCH2d archive store not unique.'}
            $root=$session.ArchiveStore.GetRootFolder()
            if([int]$root.Items.Count -ne 0 -or [int]$root.Folders.Count -gt 32){
                throw 'ARCH2d newly created archive PST root nonempty or unexpected.'
            }
            for($i=1;$i -le [int]$root.Folders.Count;$i++){
                $f=$root.Folders.Item($i)
                try{
                    if([string]$f.Name -ceq [string]$layout.ArchiveFolder){
                        throw 'ARCH2d new archive folder already exists.'
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $f}
            }
            $target=$root.Folders.Add([string]$layout.ArchiveFolder)
            if([int]$target.Items.Count -ne 0){throw 'ARCH2d target folder nonempty.'}
            $manifest=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.PreMoveManifest.1'
                RunId=$RunId;IntentSha256=$intentSha
                SourcePst=$source
                SourceStoreId=[string]$session.SourceStore.StoreID
                SourceFolderId=[string]$session.Inbox.EntryID
                ArchivePst=[string]$layout.ArchivePst
                ArchiveFolder=[string]$layout.ArchiveFolder
                ArchiveStoreId=[string]$session.ArchiveStore.StoreID
                ArchiveFolderId=[string]$target.EntryID
                PrepareOutlookProcessId=[int]$session.OutlookProcessId
                PrepareOutlookProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                BatchSize=10
                Items=@($rows.ToArray())
                WriterPermit=$false;ProductionReady=$false
            }
            [void](Assert-OPA265ARCH2dManifest -Manifest $manifest -Layout $layout -SourcePst $source -SourceStoreId ([string]$session.SourceStore.StoreID) -SourceFolderId ([string]$session.Inbox.EntryID))
            $manifestSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ManifestPath -Value $manifest
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.Prepared.1'
                Status='TenOriginalSemanticWitnessesSealedFreshArchivePreparedNoMove'
                RunId=$RunId;ManifestSha256=$manifestSha
                PreparedCount=10;ArchivePst=[string]$layout.ArchivePst
                OutlookProcessId=[int]$session.OutlookProcessId
                MoveAlreadyAttempted=$false
                ProductionReady=$false
            }
        }
        # MoveBatch and Reconcile consume the same immutable source truth.
        $manifest=Read-OPA265ARCH2c4JsonSealed -Path $layout.ManifestPath -ExpectedSha256 $ManifestSha256
        [void](Assert-OPA265ARCH2dManifest -Manifest $manifest -Layout $layout -SourcePst $source -SourceStoreId ([string]$session.SourceStore.StoreID) -SourceFolderId ([string]$session.Inbox.EntryID))
        $intent=Read-OPA265ARCH2c4JsonSealed -Path $layout.IntentPath -ExpectedSha256 ([string]$manifest.IntentSha256)
        if([string]$intent.Schema -cne '2.6.5-ARCH2d.PrepareIntent.1' -or
           [string]$intent.RunId -cne $RunId -or
           [string]$intent.SourceStoreId -cne [string]$manifest.SourceStoreId -or
           [string]$intent.SourceFolderId -cne [string]$manifest.SourceFolderId -or
           [string]$intent.DestinationPst -cne [string]$layout.ArchivePst -or
           [int]$intent.PlannedCount -ne 10 -or
           @($intent.SourceEntryIds).Count -ne 10){
            throw 'ARCH2d immutable preparation intent does not match manifest.'
        }
        for($i=0;$i -lt 10;$i++){
            if([string]$intent.SourceEntryIds[$i] -cne [string]$manifest.Items[$i].SourceEntryId){
                throw 'ARCH2d original prepared candidate index changed.'
            }
        }
        $target=Get-OPA265ARCH2dTargetFolder -Session $session -Layout $layout -Manifest $manifest
        if($Mode -ceq 'MoveBatch'){
            if([IO.File]::Exists([string]$layout.GlobalClaimPath)){
                throw 'ARCH2d global batch was already claimed. No Move retry, even with another RunId.'
            }
            if([int]$session.OutlookProcessId -ne [int]$manifest.PrepareOutlookProcessId -or
               [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$manifest.PrepareOutlookProcessStartUtcTicks){
                throw 'ARCH2d Outlook restarted after Prepare; operator must manually review, no Move.'
            }
            if([int]$target.Items.Count -ne 0){
                throw 'ARCH2d destination must be empty before claiming batch.'
            }
            for($i=1;$i -le 10;$i++){
                if([IO.File]::Exists((Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $i)) -or
                   [IO.File]::Exists((Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $i -Kind Return))){
                    throw 'ARCH2d one item already has an immutable claim/return. Never repeat batch.'
                }
            }
            # Full second pre-Move check for all ten letters before claiming any.
            for($i=0;$i -lt 10;$i++){
                $item=$null
                try{
                    $row=$manifest.Items[$i]
                    $item=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$session.SourceStore.StoreID) -EntryId ([string]$row.SourceEntryId)
                    $fresh=Get-OPA265ARCH2bMailSemanticWitness -Mail $item
                    $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $row.SourceSemanticWitness -Destination $fresh
                    if(-not $cmp.CriticalContentMatches){
                        throw ('ARCH2d original letter '+($i+1)+' changed since Prepare. No Move.')
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $item}
            }
            if(-not $PSCmdlet.ShouldProcess(([string]$layout.ArchivePst),
                'Move EXACTLY TEN existing real POP3 messages, each with independent durable per-item one-shot claim, no retry')){
                throw 'ARCH2d batch Move declined by operator.'
            }
            # One global immutable attempt claim prevents any second batch
            # execution even after process crash before a per-item claim.
            $batchClaim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.BatchOnceClaim.1'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                OriginalSourcePst=$source
                PlannedCount=10
                MoveProcessId=[int]$session.OutlookProcessId
                MoveProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                OneBatchAttemptClaimedBeforeFirstComMove=$true
                AutomaticResumeOrRetryAllowed=$false
                ProductionReady=$false
            }
            $globalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath -Value $batchClaim
            $completed=0
            for($i=0;$i -lt 10;$i++){
                $row=$manifest.Items[$i]
                $ordinal=$i+1
                $item=$null;$moved=$null;$p=$null
                try{
                    # A previous successful Move does NOT authorize skipping a
                    # failing later item. Any error stops the whole batch.
                    $item=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$session.SourceStore.StoreID) -EntryId ([string]$row.SourceEntryId)
                    $current=Get-OPA265ARCH2bMailSemanticWitness -Mail $item
                    if(-not (Compare-OPA265ARCH2bMailSemanticWitness -Source $row.SourceSemanticWitness -Destination $current).CriticalContentMatches){
                        throw ('ARCH2d item '+$ordinal+' changed before claim. Stop batch.')
                    }
                    if([int]$target.Items.Count -ne $completed){
                        throw ('ARCH2d archive count unexpected before item '+$ordinal+'; stop.')
                    }
                    $claim=[pscustomobject][ordered]@{
                        Schema='2.6.5-ARCH2d.IndividualMoveClaim.1'
                        RunId=$RunId;Ordinal=$ordinal
                        ManifestSha256=$ManifestSha256
                        BatchClaimSha256=$globalSha
                        SourceEntryId=[string]$row.SourceEntryId
                        SourceStoreId=[string]$manifest.SourceStoreId
                        ArchiveStoreId=[string]$manifest.ArchiveStoreId
                        ArchiveFolderId=[string]$manifest.ArchiveFolderId
                        ClaimedBeforeComMove=$true
                        AutomaticRetryAllowed=$false
                    }
                    $claimSha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $ordinal) -Value $claim
                    try {$moved=$item.Move($target)}
                    catch {
                        throw ('ARCH2d COM MOVE INDETERMINATE at '+$ordinal+'/10. Immutable claim SHA256='+$claimSha+
                            '. NEVER retry this batch or this letter. '+$_.Exception.Message)
                    }
                    if($null -eq $moved){throw 'ARCH2d COM Move returned null. Outcome indeterminate; no retry.'}
                    $p=$moved.Parent
                    if([string]$p.EntryID -cne [string]$manifest.ArchiveFolderId -or
                       [string]$p.StoreID -cne [string]$manifest.ArchiveStoreId){
                        throw 'ARCH2d COM Move returned item from unexpected archive; stop with claim preserved.'
                    }
                    $observation=[pscustomobject][ordered]@{
                        Schema='2.6.5-ARCH2d.MoveReturnObservation.1'
                        RunId=$RunId;Ordinal=$ordinal
                        ClaimSha256=$claimSha
                        DestinationEntryId=[string]$moved.EntryID
                        DestinationStoreId=[string]$p.StoreID
                        DestinationFolderId=[string]$p.EntryID
                        IndependentPostRestartVerificationRequired=$true
                        ProductionReady=$false
                    }
                    [void](Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $ordinal -Kind Return) -Value $observation)
                    $completed++
                }finally{
                    Release-OPA265ARCH2c4Com -Object $p
                    Release-OPA265ARCH2c4Com -Object $moved
                    Release-OPA265ARCH2c4Com -Object $item
                }
            }
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.BatchReturned.1'
                Status='TenOutlookComMovesReturnedIndependentRestartVerificationRequired'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                BatchClaimSha256=$globalSha
                Claimed=10;MoveReturned=10
                IndependentlyVerified=0
                ArchivePst=[string]$layout.ArchivePst
                AutomaticRetryAllowed=$false;ProductionReady=$false
            }
        }
        # Reconcile: read only, no PST mount, no file writes, no MailItem.Move.
        $global=Read-OPA265ARCH2c4JsonSealed -Path $layout.GlobalClaimPath -ExpectedSha256 $BatchClaimSha256
        if([string]$global.Schema -cne '2.6.5-ARCH2d.BatchOnceClaim.1' -or
           [string]$global.RunId -cne $RunId -or
           [string]$global.ManifestSha256 -cne $ManifestSha256 -or
           -not [bool]$global.OneBatchAttemptClaimedBeforeFirstComMove -or
           [bool]$global.AutomaticResumeOrRetryAllowed){
            throw 'ARCH2d invalid original global batch claim; no assumption of success.'
        }
        $restart=([int]$session.OutlookProcessId -ne [int]$global.MoveProcessId -and
                  [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$global.MoveProcessStartUtcTicks)
        if(-not $restart){throw 'ARCH2d independent reconciliation requires NEW Outlook process after MoveBatch.'}
        $targetItems=$target.Items
        $targetCount=[int]$targetItems.Count
        if($targetCount -lt 0 -or $targetCount -gt 128){
            throw 'ARCH2d archive item count out of bounded reconciliation range.'
        }
        $destinationBySignature=@{}
        $unknownDestination=0
        $duplicates=0
        for($j=1;$j -le $targetCount;$j++){
            $d=$null
            try{
                $d=$targetItems.Item($j)
                if($null -eq $d -or [int]$d.Class -ne 43){
                    $unknownDestination++
                    continue
                }
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $d
                $sig=Get-OPA265ARCH2dSemanticSignature -Witness $w
                if($destinationBySignature.ContainsKey($sig)){
                    $duplicates++
                }else{
                    $destinationBySignature[$sig]=$w
                }
            }finally{Release-OPA265ARCH2c4Com -Object $d}
        }
        $observations=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt 10;$i++){
            $row=$manifest.Items[$i]
            $ordinal=$i+1
            $claimPath=Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $ordinal
            $returnPath=Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $ordinal -Kind Return
            $claimed=[IO.File]::Exists($claimPath)
            $hasReturn=[IO.File]::Exists($returnPath)
            $claimMatches=$false
            $claimFileSha=''
            if($claimed){
                try{
                    $claimFileSha=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    $claim=Read-OPA265ARCH2c4JsonSealed -Path $claimPath -ExpectedSha256 $claimFileSha
                    $claimMatches=([string]$claim.Schema -ceq '2.6.5-ARCH2d.IndividualMoveClaim.1' -and
                        [string]$claim.RunId -ceq $RunId -and
                        [int]$claim.Ordinal -eq $ordinal -and
                        [string]$claim.SourceEntryId -ceq [string]$row.SourceEntryId -and
                        [string]$claim.ManifestSha256 -ceq $ManifestSha256 -and
                        [string]$claim.BatchClaimSha256 -ceq $BatchClaimSha256 -and
                        [bool]$claim.ClaimedBeforeComMove -and
                        -not [bool]$claim.AutomaticRetryAllowed)
                }catch{$claimMatches=$false}
            }
            $sourcePresence=Get-OPA265ARCH2dSourcePresence -Namespace $session.Namespace -EntryId ([string]$row.SourceEntryId) -StoreId ([string]$manifest.SourceStoreId) -FolderId ([string]$manifest.SourceFolderId)
            $contentMatches=$false
            $hasMatchingTarget=$destinationBySignature.ContainsKey([string]$row.SemanticSignature)
            if($hasMatchingTarget){
                $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $row.SourceSemanticWitness -Destination $destinationBySignature[[string]$row.SemanticSignature]
                $contentMatches=[bool]$cmp.CriticalContentMatches
            }
            $status='ManualReviewRequired'
            if($claimMatches -and $sourcePresence -eq 0 -and $hasMatchingTarget -and
               $contentMatches -and $duplicates -eq 0 -and $unknownDestination -eq 0){
                $status='MovedAndSemanticallyMatched'
            }elseif(-not $claimed -and -not $hasReturn -and $sourcePresence -eq 1 -and -not $hasMatchingTarget){
                $status='NotAttemptedOriginalSourcePresent'
            }
            $observations.Add([pscustomobject][ordered]@{
                Ordinal=$ordinal;SourceEntryId=[string]$row.SourceEntryId
                MoveClaimExists=$claimed;MoveReturnExists=$hasReturn
                ClaimProvenanceValid=$claimMatches
                SourceOriginalEntryIdObservedCount=$sourcePresence
                DestinationSemanticSelectorMatched=$hasMatchingTarget
                FullSemanticContentMatches=$contentMatches
                Status=$status
            })|Out-Null
        }
        $decision=Get-OPA265ARCH2dReconcileDecision -ItemResults @($observations.ToArray()) -DestinationItemCount $targetCount -RestartConfirmed $restart
        if($unknownDestination -gt 0 -or $duplicates -gt 0){
            $decision.Status='ManualReviewRequiredNoAutomaticRetry'
            $decision.IndependentlyVerifiedAllTen=$false
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.IndependentPostRestartReconciliation.1'
            Status=[string]$decision.Status
            RunId=$RunId;ManifestSha256=$ManifestSha256
            BatchClaimSha256=$BatchClaimSha256
            VerifiedMoved=[int]$decision.VerifiedMoved
            NotAttempted=[int]$decision.NotAttempted
            Claimed=[int]$decision.Claimed
            Planned=10
            TargetFolderItemCount=$targetCount
            UnknownDestinationItems=$unknownDestination
            DuplicateSemanticSelectors=$duplicates
            OutlookRestartConfirmed=$restart
            Items=@($observations.ToArray())
            OriginalMoveMayBeRetried=$false
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $items
        Release-OPA265ARCH2c4Com -Object $target
        Release-OPA265ARCH2c4Com -Object $root
        Release-OPA265ARCH2c4Com -Object $moved
        Close-OPA265ARCH2dSession -Session $session
    }
}
