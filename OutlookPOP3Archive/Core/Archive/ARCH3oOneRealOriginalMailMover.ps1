#requires -Version 5.1
# ARCH3o exact-one REAL TEST POP3 PST operator move inside original MailMover.
# No automatic retry; original journal remains Intent, shared index untouched.
. (Join-Path $PSScriptRoot 'ARCH3nPinnedRealIntentBridge.ps1')

function Get-OPA265ARCH3oOneShotStatus {
    [CmdletBinding()]
    param([string]$RunId,[string]$IntentSha256,[string]$JournalSha256)
    if($RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       $IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       $JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'){throw 'ARCH3o exact operator RunId/sha required.'}
    $l=Get-OPA265ARCH3jLayout -RunId $RunId
    if(-not [IO.Directory]::Exists([string]$l.Root) -or
       (([IO.File]::GetAttributes([string]$l.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'ARCH3o unsafe original intent directory.'}
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$l.Root))
    $intent=Read-OPA265ARCH3cPinnedJson -Path ([string]$l.IntentPath) -ExpectedSha256 $IntentSha256
    $events=Read-OPAOperationJournal -Path ([string]$l.JournalPath)
    if((Get-FileHash -LiteralPath ([string]$l.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $JournalSha256 -or
       @($events.Events).Count -ne 1 -or [bool]$events.TrailingPartial -or
       [string]$events.Events[0].Phase -cne 'Intent' -or
       [string]$events.Events[0].OperationId -cne [string]$intent.OperationId -or
       [string]$intent.RunId -cne $RunId -or [bool]$intent.WriterPermit){throw 'ARCH3o original journal/intent changed. Manual review.'}
    $allowed=@('original-prepare-intent.json','original-operation-journal.jsonl','ARCH3o-WriterEntry.json',
        'ARCH3o-DestinationReady.json','ARCH3o-MoveClaimed.json',
        'ARCH3o-ProviderInvocation.json','ARCH3o-MoveReturned.json')
    $sha=@{}
    foreach($path in @([IO.Directory]::GetFileSystemEntries([string]$l.Root))){
        $name=[IO.Path]::GetFileName($path)
        if($allowed -cnotcontains $name -or -not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3o unexpected evidence; never replay.'
        }
        $sha[$name]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3o.OneShotForensicStatus.1'
        Status='ProtectedOriginalIntentAndWriterEvidenceReadOnlyNeverReplay'
        RunId=$RunId;EvidenceSha256=$sha
        WriterEntryExists=$sha.ContainsKey('ARCH3o-WriterEntry.json')
        DestinationReadyExists=$sha.ContainsKey('ARCH3o-DestinationReady.json')
        MoveClaimed=$sha.ContainsKey('ARCH3o-MoveClaimed.json')
        ProviderInvocationExists=$sha.ContainsKey('ARCH3o-ProviderInvocation.json')
        MoveReturnedReceiptExists=$sha.ContainsKey('ARCH3o-MoveReturned.json')
        OriginalJournalIntentPreserved=$true
        OriginalDuplicateIndexWritten=$false
        IndependentPostRestartVerified=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3oOneRealPop3Move {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Move','Status')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$IntentSha256,
        [Parameter(Mandatory=$true)][string]$JournalSha256,
        [switch]$ConfirmOneRealMove
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3o requires native Windows PowerShell 5.1.'}
    if($Mode -cne 'Move' -and $ConfirmOneRealMove){throw 'ARCH3o confirmation only permitted for Move.'}
    if($Mode -ceq 'Status'){return (Get-OPA265ARCH3oOneShotStatus -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256)}
    # Existing ARCH3n reader insists the original Prepare directory has
    # EXACT TWO files: any partial writer entry blocks Plan/Audit/Move replay.
    $p=Get-OPA265ARCH3nPinnedRealRoute -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    $l=Get-OPA265ARCH3jLayout -RunId $RunId
    if(@([IO.Directory]::GetFileSystemEntries([string]$l.Root)).Count -ne 2){throw 'ARCH3o writer evidence already exists; never retry.'}
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.Plan.1';Status='PinnedOriginalOneRealTestPop3MovePlanNoOutlookNoWrites'
            RunId=$RunId;SourceEntryId=[string]$p.SourceEntryId
            ExistingPart1=[string]$p.ExistingPart1;UnusedPart2=[string]$p.UnusedPart2
            OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
            OriginalOperationJournalIntentVerified=$true;OriginalSharedIndexReadOnly=$true
            LiveMovePerformed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3o Audit/Move requires STA.'}
    if($Mode -ceq 'Move'){
        if(-not $ConfirmOneRealMove){throw 'ARCH3o requires explicit -ConfirmOneRealMove for destructive TEST PST.'}
        if(-not $PSCmdlet.ShouldProcess([string]$p.SourceEntryId,'ONE real original MailMover Move into NEW test Year2020 Part2, NEVER retry')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3o.WhatIf.1';Status='WhatIfBeforeOutlookAndPstWrites';MoveClaimed=$false;WriterPermit=$false;ProductionReady=$false}
        }
    }
    $session=$null;$mail=$null;$parent=$null;$archive=$null;$dest=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA) -SourcePst ([string]$p.RealSourcePst)
        if(-not [bool]$session.Scope.Approved){throw 'ARCH3o original real POP3 scope rejected.'}
        $sourceStoreId=[string]$session.SourceStore.StoreID
        if((Get-OPA265ARCH2bTextSha256 -Text $sourceStoreId) -cne [string]$p.SourceStoreIdSha256){throw 'ARCH3o source StoreID changed.'}
        $mail=$session.Namespace.GetItemFromID([string]$p.SourceEntryId,$sourceStoreId)
        if($null -eq $mail -or [int]$mail.Class -ne 43 -or [string]$mail.EntryID -cne [string]$p.SourceEntryId){throw 'ARCH3o exact mail missing.'}
        $parent=$mail.Parent
        if($null -eq $parent -or [string]$parent.EntryID -cne [string]$p.SourceFolderEntryId -or
           [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
           [string]$parent.StoreID -cne $sourceStoreId -or
           [string]$parent.FolderPath -cne '\\info@stios.ru\Входящие'){throw 'ARCH3o exact original POP3 Inbox drift.'}
        $sealed=Get-OPA265ARCH3jSealedSource -SealRunId ([string]$p.SourceSealRunId) -SealSha256 ([string]$p.SourceSealSha256)
        $date=Get-OPAArchiveItemDate -Item $mail
        if($null -eq $date -or ([datetime]$date).Ticks -ne [long]$sealed.ArchiveDateLocalTicks){throw 'ARCH3o archive date changed.'}
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $w -ExpectedOriginalWitnessSha256 ([string]$p.OriginalWitnessSha256))
        $contract=Get-OPA265ARCH3jOriginalRoutePlan -Sealed $sealed -RunId $RunId -SourceStoreId $sourceStoreId
        if([string]$contract.ContractSha256 -cne [string]$p.OriginalContractSha256 -or
           [string]$contract.OperationId -cne [string]$p.OriginalOperationId -or
           [string]$contract.PlannedArchivePst -cne [string]$p.UnusedPart2){throw 'ARCH3o original year/part contract changed.'}
        $index=Get-OPA265ARCH3jIndexSafety -Part1 ([string]$p.ExistingPart1) -SourceEntryId ([string]$p.SourceEntryId)
        if(-not [bool]$index.Approved -or [int]$index.EntryCount -ne 500){throw 'ARCH3o shared DuplicateIndex changed.'}
        if([IO.File]::Exists([string]$p.UnusedPart2) -or [IO.Directory]::Exists([string]$p.UnusedPart2) -or
           [IO.FileInfo]::new([string]$p.ExistingPart1).Length -ne 271360 -or
           $null -ne (Get-OpaStoreByPathCached -Namespace $session.Namespace -Path ([string]$p.UnusedPart2))){
            throw 'ARCH3o old Part1 changed or new Part2 already occupied/mounted.'
        }
        if($Mode -ceq 'Audit'){
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3o.Audit.1';Status='ExactOriginalRealSourceFullWitnessAndUnusedPart2ReadOnlyNoMove'
                RunId=$RunId;SourceEntryId=[string]$p.SourceEntryId;OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
                ExistingPart1LengthBytes=[long]271360;NewPart2Unused=$true
                OriginalSharedIndexEntryCount=500;OriginalJournalIntentPinned=$true
                OutlookProcessId=[int]$session.OutlookProcessId
                OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
                MoveClaimed=$false;LiveMovePerformed=$false;WriterPermit=$false;ProductionReady=$false
            }
        }
        if(@([IO.Directory]::GetFileSystemEntries([string]$l.Root)).Count -ne 2){throw 'ARCH3o writer evidence appeared before boundary. STOP.'}
        $root=[string]$l.Root
        # First no-replay CreateNew marker even BEFORE allocating the new PST.
        $writer=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.WriterEntry.1';RunId=$RunId;IntentSha256=$IntentSha256
            JournalSha256=$JournalSha256;OperationId=[string]$p.OriginalOperationId
            SourceEntryId=[string]$p.SourceEntryId;OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
            NewArchivePst=[string]$p.UnusedPart2;OriginalSharedIndexReadOnly=$true
            OutlookProcessId=[int]$session.OutlookProcessId;OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $writerSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root 'ARCH3o-WriterEntry.json') -Record $writer
        $archive=New-OPAArchivePst -Namespace $session.Namespace -ArchivePst ([string]$p.UnusedPart2) -AccountEmail 'info@stios.ru' -ARCH3oRequireNewUnusedPst
        if($null -eq $archive -or
           -not [string]::Equals([IO.Path]::GetFullPath([string]$archive.FilePath),[IO.Path]::GetFullPath([string]$p.UnusedPart2),[StringComparison]::OrdinalIgnoreCase) -or
           [string]$archive.StoreID -ceq $sourceStoreId -or
           [string]$archive.StoreID -ceq [string]$session.DefaultStoreId -or
           -not [IO.File]::Exists([string]$p.UnusedPart2) -or
           [IO.FileInfo]::new([string]$p.UnusedPart2).Length -le 0){throw 'ARCH3o original fresh Part2 store invalid. Never retry.'}
        foreach($a in @($session.Accounts)){
            if([string]$a.DeliveryStoreId -ceq [string]$archive.StoreID){throw 'ARCH3o archive became an account delivery store.'}
        }
        $dest=Get-OPAArchiveFolder -ArchiveStore $archive -SourceFolderName ([string]$parent.Name) -SourceFolderPath ([string]$parent.FolderPath) -ReceivedTime ([datetime]$date) -Grouping Year
        if($null -eq $dest -or [string]::IsNullOrWhiteSpace([string]$dest.EntryID) -or
           [string]$dest.StoreID -cne [string]$archive.StoreID -or
           -not ([string]$dest.FolderPath).EndsWith('\2020\Входящие',[StringComparison]::OrdinalIgnoreCase) -or
           [int]$dest.Items.Count -ne 0 -or
           [IO.FileInfo]::new([string]$p.ExistingPart1).Length -ne 271360){throw 'ARCH3o real target not empty Year2020 Inbox or old Part1 changed.'}
        $last=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $last -ExpectedOriginalWitnessSha256 ([string]$p.OriginalWitnessSha256))
        $ready=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.DestinationReady.1';RunId=$RunId;WriterEntrySha256=$writerSha
            NewArchivePst=[string]$p.UnusedPart2;DestinationStoreId=[string]$archive.StoreID
            DestinationFolderEntryId=[string]$dest.EntryID;OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
            InitialItemCount=0;MoveClaimed=$false;ProductionReady=$false
        }
        $readySha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root 'ARCH3o-DestinationReady.json') -Record $ready
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.RealOneShotMoveClaim.1';RunId=$RunId
            IntentSha256=$IntentSha256;JournalSha256=$JournalSha256
            WriterEntrySha256=$writerSha;DestinationReadySha256=$readySha
            SourceEntryId=[string]$p.SourceEntryId;OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
            NewArchivePst=[string]$p.UnusedPart2;DestinationStoreId=[string]$archive.StoreID
            DestinationFolderEntryId=[string]$dest.EntryID
            OutlookProcessId=[int]$session.OutlookProcessId;OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            OperatorApprovedOneRealMove=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $claimSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root 'ARCH3o-MoveClaimed.json') -Record $claim
        $result=Invoke-OPA265ARCH3oOneOriginalMailMoverProviderCall -Mail $mail -Folder $dest -RunId $RunId -ClaimSha256 $claimSha
        if(-not [bool]$result.OneMoveReturned -or
           [string]$result.DestinationEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$'){throw 'ARCH3o COM outcome UNKNOWN, no automatic retry.'}
        $receipt=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.MoveReturned.1';RunId=$RunId
            SourceEntryId=[string]$p.SourceEntryId;ArchiveEntryId=[string]$result.DestinationEntryId
            NewArchivePst=[string]$p.UnusedPart2
            OriginalWitnessSha256=[string]$p.OriginalWitnessSha256
            OriginalContractSha256=[string]$p.OriginalContractSha256
            MoveClaimSha256=$claimSha;ProviderInvocationSha256=[string]$result.ProviderInvocationSha256
            DestinationStoreId=[string]$archive.StoreID;DestinationFolderEntryId=[string]$dest.EntryID
            OutlookProcessId=[int]$session.OutlookProcessId;OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            OriginalMailMoverUsed=$true;IndependentPostRestartVerified=$false
            OriginalJournalReconciled=$false;DuplicateIndexWritten=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $receiptSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root 'ARCH3o-MoveReturned.json') -Record $receipt
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3o.LiveOneShotReturned.1'
            Status='OneRealPop3OriginalMailMoverReturnedIndependentOutlookRestartRequired'
            RunId=$RunId;SourceEntryId=[string]$p.SourceEntryId
            ArchiveEntryId=[string]$result.DestinationEntryId;NewArchivePst=[string]$p.UnusedPart2
            WriterEntrySha256=$writerSha;DestinationReadySha256=$readySha
            MoveClaimSha256=$claimSha;ProviderInvocationSha256=[string]$result.ProviderInvocationSha256
            MoveReceiptSha256=$receiptSha;MoveClaimed=$true;OneRealMoveReturned=$true
            IndependentPostRestartVerified=$false;OriginalJournalReconciled=$false
            DuplicateIndexWritten=$false;AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $dest
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $mail
        Close-OPA265ARCH2dSession -Session $session
    }
}
