#requires -Version 5.1
# ARCH3x: source-backed ten original Intent readback + fake-only durable
# provider fences in the EXISTING MailMover. No real Outlook/PST writer.
. (Join-Path $PSScriptRoot 'ARCH3w1SemanticPart2Intents.ps1')
. (Join-Path $PSScriptRoot 'ARCH3rTenItemSyntheticIntegration.ps1')
. (Join-Path $PSScriptRoot 'MailMover.ps1')

function Assert-OPA265ARCH3xSyntheticWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Workspace)
    $path=[IO.Path]::GetFullPath($Workspace).TrimEnd([char]92,[char]47)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    if(-not $path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($path) -cnotmatch '^OPA265-ARCH3x-SYNTH-[a-f0-9]{32}$' -or
       -not [IO.Directory]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3x only accepts a private existing OS TEMP fake workspace.'
    }
    return $path
}

function Get-OPA265ARCH3xSyntheticStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Workspace)
    $root=Assert-OPA265ARCH3xSyntheticWorkspace -Workspace $Workspace
    foreach($f in @(Get-ChildItem -LiteralPath $root -File -Force)){
        if($f.Name -cnotmatch '^(0[1-9]|10)-(Claim|Invocation|Returned)\.json$' -or
           (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3x unexpected or redirected evidence file: STOP.'
        }
    }
    $claimCount=0;$invocationCount=0;$returnedCount=0;$gap=0
    for($i=1;$i -le 10;$i++){
        $prefix=('{0:00}' -f $i)
        $c=Join-Path $root ($prefix+'-Claim.json')
        $v=Join-Path $root ($prefix+'-Invocation.json')
        $r=Join-Path $root ($prefix+'-Returned.json')
        $hasC=[IO.File]::Exists($c);$hasV=[IO.File]::Exists($v);$hasR=[IO.File]::Exists($r)
        if(($hasV -and -not $hasC) -or ($hasR -and -not $hasV) -or
           ($gap -gt 0 -and ($hasC -or $hasV -or $hasR))){
            throw 'ARCH3x synthetic evidence sequence is non-prefix or orphaned; NO REPLAY.'
        }
        if($hasC){
            $claim=Read-OPA265ARCH3cPinnedJson -Path $c -ExpectedSha256 (Get-FileHash -LiteralPath $c -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$claim.Schema -cne '2.6.5-ARCH3x.SyntheticMoveClaim.1' -or
               [int]$claim.Ordinal -ne $i -or -not [bool]$claim.SyntheticOnly -or
               [bool]$claim.AutomaticRetryAllowed){throw 'ARCH3x corrupt synthetic claim.'}
            $claimCount++
        }
        if($hasV){
            $inv=Read-OPA265ARCH3cPinnedJson -Path $v -ExpectedSha256 (Get-FileHash -LiteralPath $v -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$inv.Schema -cne '2.6.5-ARCH3x.SyntheticProviderInvocation.1' -or
               [string]$inv.ClaimSha256 -cne (Get-FileHash -LiteralPath $c -Algorithm SHA256).Hash.ToLowerInvariant() -or
               [string]$inv.SourceEntryId -cne [string]$claim.SourceEntryId -or
               [int]$inv.Ordinal -ne $i){throw 'ARCH3x synthetic invocation/claim mismatch.'}
            $invocationCount++
        }
        if($hasR){
            $receipt=Read-OPA265ARCH3cPinnedJson -Path $r -ExpectedSha256 (Get-FileHash -LiteralPath $r -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$receipt.Schema -cne '2.6.5-ARCH3x.SyntheticMoveReturned.1' -or
               [string]$receipt.ProviderInvocationSha256 -cne (Get-FileHash -LiteralPath $v -Algorithm SHA256).Hash.ToLowerInvariant() -or
               [string]$receipt.ClaimSha256 -cne [string]$inv.ClaimSha256 -or
               [string]$receipt.DestinationEntryId -cne [string]$claim.DestinationEntryId){
                throw 'ARCH3x synthetic return/claim SHA chain mismatch.'
            }
            $returnedCount++
        }
        if(((-not $hasC) -or (-not $hasV) -or (-not $hasR)) -and $gap -eq 0){$gap=$i}
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x.SyntheticOriginalProviderStatus.1'
        Status=if($returnedCount -eq 10){'TenSyntheticOriginalProviderReturnsNoRealWriter'}else{'PartialSyntheticProviderEvidenceNoReplay'}
        Workspace=$root;Expected=10;Claims=$claimCount
        ProviderInvocations=$invocationCount;Returned=$returnedCount
        FirstUnfinishedOrdinal=$gap;OriginalMailMoverSyntheticProviderUsed=$true
        RealOutlookContacted=$false;RealPstOpenedOrWritten=$false
        OriginalSharedIndexWritten=$false;AutomaticMoveRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3xSyntheticTen {
    [CmdletBinding()]
    param([ValidateSet('None','AfterClaim','AfterInvocation','ProviderThrows','AfterMoveReturned')][string]$Fault='None',
          [ValidateRange(1,10)][int]$FaultAt=4)
    $root=Join-Path ([IO.Path]::GetTempPath()) ('OPA265-ARCH3x-SYNTH-'+[guid]::NewGuid().ToString('N'))
    if([IO.Directory]::Exists($root)){throw 'ARCH3x synthetic directory exists; NO REPLAY.'}
    [void][IO.Directory]::CreateDirectory($root)
    [void](Assert-OPA265ARCH3xSyntheticWorkspace -Workspace $root)
    $rows=@(New-OPA265ARCH3rTenSyntheticPlan)
    if($rows.Count -ne 10){throw 'ARCH3x original full witness fake ten plan missing.'}
    $folder=[pscustomobject]@{EntryID='ARCH3X-FAKE-DEST';SyntheticOnly=$true}
    $runId=[guid]::NewGuid().ToString('D')
    $stop=''
    for($i=1;$i -le 10;$i++){
        $row=$rows[$i-1]
        if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $row.SourceWitness) -or
           [string]$row.OriginalSourceWitnessDigest -cnotmatch '^[a-f0-9]{64}$'){
            throw 'ARCH3x original ARCH2b full synthetic source witness invalid.'
        }
        $prefix=('{0:00}' -f $i)
        $claimPath=Join-Path $root ($prefix+'-Claim.json')
        $invokePath=Join-Path $root ($prefix+'-Invocation.json')
        $returnPath=Join-Path $root ($prefix+'-Returned.json')
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x.SyntheticMoveClaim.1'
            RunId=$runId;Ordinal=$i
            SourceEntryId=[string]$row.SourceEntryId
            DestinationEntryId=[string]$row.ArchiveEntryId
            DestinationFolderEntryId=[string]$folder.EntryID
            WitnessSha256=[string]$row.OriginalSourceWitnessDigest
            SyntheticOnly=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $claimSha=Write-OPA265ARCH3cJsonOnce -Path $claimPath -Record $claim
        try{
            if($Fault -ceq 'AfterClaim' -and $i -eq $FaultAt){throw 'ARCH3x fault after durable claim.'}
            $mail=[pscustomobject]@{
                EntryID=[string]$row.SourceEntryId;TargetEntryId=[string]$row.ArchiveEntryId
                Class=43;SyntheticOnly=$true;MoveCalls=0
                ThrowOnMove=($Fault -ceq 'ProviderThrows' -and $i -eq $FaultAt)
            }
            $mail | Add-Member -MemberType ScriptMethod -Name Move -Value {
                param($Destination)
                $this.MoveCalls=[int]$this.MoveCalls+1
                if($this.ThrowOnMove){throw 'ARCH3x fake Outlook provider exception.'}
                return [pscustomobject]@{Class=43;EntryID=[string]$this.TargetEntryId}
            }
            $result=Invoke-OPA265ARCH3xFakeOnlyOriginalProviderCall -Mail $mail -Folder $folder -ClaimPath $claimPath -ExpectedClaimSha256 $claimSha -InvocationPath $invokePath -FaultAfterInvocation:($Fault -ceq 'AfterInvocation' -and $i -eq $FaultAt)
            if($Fault -ceq 'AfterMoveReturned' -and $i -eq $FaultAt){throw 'ARCH3x fault after fake Move returned.'}
            $receipt=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3x.SyntheticMoveReturned.1'
                RunId=$runId;Ordinal=$i;ClaimSha256=$claimSha
                ProviderInvocationSha256=[string]$result.ProviderInvocationSha256
                DestinationEntryId=[string]$result.DestinationEntryId
                FakeOnly=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
            }
            [void](Write-OPA265ARCH3cJsonOnce -Path $returnPath -Record $receipt)
        }catch{
            $stop=[string]$_.Exception.Message
            break
        }
    }
    $result=Get-OPA265ARCH3xSyntheticStatus -Workspace $root
    $result | Add-Member -NotePropertyName Fault -NotePropertyValue $Fault
    $result | Add-Member -NotePropertyName FaultAt -NotePropertyValue $FaultAt
    $result | Add-Member -NotePropertyName StopReason -NotePropertyValue $stop
    return $result
}

function Invoke-OPA265ARCH3xOriginalBatchFence {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','ReviewPrepared','Synthetic','Inspect')][string]$Mode,
        [string]$RunId='',
        [string]$SealSha256='',
        [string]$ManifestSha256='',
        [string]$JournalSha256='',
        [string]$Workspace='',
        [ValidateSet('None','AfterClaim','AfterInvocation','ProviderThrows','AfterMoveReturned')][string]$Fault='None',
        [ValidateRange(1,10)][int]$FaultAt=4
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3x requires Windows PowerShell 5.1.'
    }
    if($Mode -ceq 'Synthetic'){
        if($RunId -or $SealSha256 -or $ManifestSha256 -or $JournalSha256 -or $Workspace){
            throw 'ARCH3x synthetic mode rejects all real operator pins or paths.'
        }
        if(-not $PSCmdlet.ShouldProcess('OS TEMP fake Outlook','Write ten synthetic claim/provider fences and invoke fake Move')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3x.WhatIf.1';Status='SyntheticWhatIfNoWrites';WriterPermit=$false;ProductionReady=$false}
        }
        return (Invoke-OPA265ARCH3xSyntheticTen -Fault $Fault -FaultAt $FaultAt)
    }
    if($Fault -cne 'None' -or $FaultAt -ne 4){throw 'ARCH3x fault injection restricted to Synthetic.'}
    if($Mode -ceq 'Inspect'){
        if($RunId -or $SealSha256 -or $ManifestSha256 -or $JournalSha256){throw 'ARCH3x Inspect is fake OS TEMP only.'}
        return (Get-OPA265ARCH3xSyntheticStatus -Workspace $Workspace)
    }
    if($Workspace){throw 'ARCH3x Plan/ReviewPrepared forbids synthetic workspace.'}
    if($RunId -cne '093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'){throw 'ARCH3x requires exact original ARCH3v operator RunId.'}
    if($Mode -ceq 'Plan'){
        if($SealSha256 -or $ManifestSha256 -or $JournalSha256){throw 'ARCH3x Plan refuses unreviewed hashes.'}
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x.Plan.1';Status='TenOriginalIntentsBatchSafetyPlanNoRealMove'
            RunId=$RunId;Expected=10;ArchiveYear=2020;ArchivePart=3
            OriginalMailMoverRequired=$true;OriginalPostRestartVerifierRequired=$true
            PerItemDurableMoveClaimRequired=$true;PerItemDurableProviderInvocationRequired=$true
            IndexCommitBeforeIndependentVerifierAllowed=$false
            RealOutlookContacted=$false;RealPstOpenedOrWritten=$false;RealMailMovePerformed=$false
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    foreach($sha in @($SealSha256,$ManifestSha256,$JournalSha256)){
        if($sha -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3x ReviewPrepared requires three externally pinned SHA256 hashes.'}
    }
    $layout=Get-OPA265ARCH3w1Layout -RunId $RunId
    $r=Test-OPA265ARCH3w1PreparedReadback -Layout $layout -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    if([int]$r.PreparedIntentCount -ne 10 -or [int]$r.OriginalJournalEventCount -ne 10 -or
       -not [bool]$r.Part2OriginalArchiveVerifierProven -or [bool]$r.MoveClaimed -or
       [bool]$r.WriterPermit){throw 'ARCH3x original sealed ten Intent/archived Part2 proof incomplete.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x.ReviewPrepared.1'
        Status='TenOriginalProtectedIntentsReadbackNoRealMoveAuthorization'
        RunId=$RunId;ManifestSha256=$ManifestSha256;JournalSha256=$JournalSha256
        PreparedIntentCount=10;ArchiveYear=2020;ArchivePart=3
        OriginalArchiveVerifierRequired=$true
        RealOutlookContacted=$false;RealPstOpenedOrWritten=$false
        RealMailMovePerformed=$false;AutomaticMoveRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
