#requires -Version 5.1
# BW4k7u: PURE in-memory synthetic POP3 multi-item preflight.
# No Outlook COM, real or disposable PST files, disk journal/Claim, or actual crash durability.
. (Join-Path $PSScriptRoot 'BW4k7tSemanticAcceptancePolicy265.ps1')
. (Join-Path $PSScriptRoot 'BW4k7rYearCapacityPlan265.ps1')

function Get-OPA265BW4k7uHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $h=[Security.Cryptography.SHA256]::Create()
    try {
        $b=[Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-','').ToLowerInvariant()
    }finally{$h.Dispose()}
}
function Get-OPA265BW4k7uByteHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}
    finally{$h.Dispose()}
}
function Copy-OPA265BW4k7uObject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Value)
    return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12 -Compress))
}
function New-OPA265BW4k7uSyntheticSuite {
    [CmdletBinding()]
    param([string]$SuiteId=([guid]::NewGuid().ToString('D')))
    $g=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$g) -or
       $g -eq [guid]::Empty -or $SuiteId -cne $g.ToString('D')){
        throw 'BW4k7u canonical nonempty GUID SuiteId required.'
    }
    $spec=@(
        @('Inbox2020Plain','Mail','Inbox','\Inbox',2020,0,0),
        @('Inbox2021Unicode','Mail','Inbox','\Inbox',2021,0,0),
        @('Inbox2024Html','Mail','Inbox','\Inbox',2024,0,0),
        @('Inbox2025Attachment1K','Mail','Inbox','\Inbox',2025,1024,0),
        @('Sent2023Unicode','Mail','SentItems','\Sent Items',2023,0,0),
        @('Sent2025Attachment256K','Mail','SentItems','\Sent Items',2025,262144,0),
        @('User2022Nested','Mail','UserMail','\Projects\Alpha\2022',2022,2048,0),
        @('User2024HtmlAttach','Mail','UserMail','\Projects\Beta',2024,1024,0),
        @('Inbox2026Retained','Mail','Inbox','\Inbox',2026,0,1),
        @('InboxNdrRetained','ReportNdr','Inbox','\Inbox',2020,0,1),
        @('InboxReadReceiptRetained','ReportReadReceipt','Inbox','\Inbox',2021,0,1),
        @('InboxMeetingRetained','MeetingRequest','Inbox','\Inbox',2024,0,1)
    )
    $cases=New-Object 'System.Collections.Generic.List[object]'
    for($i=0;$i -lt $spec.Count;$i++){
        $p=$spec[$i];$name=[string]$p[0];$kind=[string]$p[1]
        $n=[int]$p[5];$attach=New-Object 'System.Collections.Generic.List[object]'
        if($n -gt 0){
            $bytes=New-Object 'byte[]' $n
            for($j=0;$j -lt $n;$j++){$bytes[$j]=[byte](($j*31+$i*13+7)%256)}
            $encoded=[Convert]::ToBase64String($bytes)
            $attach.Add([pscustomobject][ordered]@{
                Name=('BW4k7u-'+$name+'.bin')
                ByteCount=$n
                BytesBase64=$encoded
                PayloadSha256=(Get-OPA265BW4k7uByteHash -Bytes $bytes)
            })
        }
        $cls=if($kind -eq 'Mail'){43}elseif($kind -eq 'MeetingRequest'){53}else{46}
        $message=switch($kind){
            'Mail'{'IPM.Note'}
            'ReportNdr'{'Report.IPM.Note.NDR'}
            'ReportReadReceipt'{'Report.IPM.Note.IPNRN'}
            'MeetingRequest'{'IPM.Schedule.Meeting.Request'}
        }
        $body='Synthetic BW4k7u '+$name+'; no customer message content'
        if($name -match 'Unicode'){$body+=' Привет, мир.'}
        $html=if($name -match 'Html'){'<html><body><b>'+ $name +'</b></body></html>'}else{''}
        $hasAttach=if($n -gt 0){16L}else{0L}
        $id='SYNTH-'+$SuiteId+'-'+('{0:D2}' -f ($i+1))
        $year=[int]$p[4]
        $cases.Add([pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7u.SyntheticCase.1'
            SuiteId=$SuiteId;CaseId=$id;Name=$name;Kind=$kind;Class=$cls
            MessageClass=$message
            Role=[string]$p[2];SourceFolderPath=[string]$p[3];Year=$year
            EligibleForArchive=([int]$p[6] -eq 0)
            Subject=('BW4k7u '+$name+' '+$SuiteId)
            Sender='synthetic-sender@example.invalid'
            RecipientsTo=@('to-a@example.invalid','to-b@example.invalid')
            RecipientsCc=@('copy@example.invalid')
            RecipientsBcc=if($p[2] -eq 'SentItems'){@('bcc@example.invalid')}else{@()}
            Body=$body;HtmlBody=$html
            TransportHeaders='X-Synthetic-Only: BW4k7u'
            ReceivedUtcTicks=[long](637134336000000000L+([long]$year-2020)*315360000000000L+$i*10000000L)
            SentUtcTicks=[long](637134335000000000L+([long]$year-2020)*315360000000000L+$i*10000000L)
            ReadState='Read';Categories='BW4k7uSynthetic';FollowupFlag='NoFlag'
            BeforeRawMessageFlags=[long](65539L -bor $hasAttach)
            AfterRawMessageFlags=[long](3L -bor $hasAttach)
            SourceEntryId=('SYNTH-SOURCE-'+$id);DestinationEntryId=('SYNTH-DEST-'+$id)
            LogicalSizeBytes=[long](8192+$n+$body.Length*2+$html.Length*2)
            ModeledSizeDeltaBytes=[long]38
            Attachments=@($attach.ToArray())
            SyntheticOnly=$true;OutlookMAPIObserved=$false;ProductionReady=$false
        })
    }
    $arr=@($cases.ToArray())
    $digest=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $arr -Depth 12 -Compress)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticMultiItemSuite.1'
        SuiteId=$SuiteId
        Cases=$arr;FixtureCount=12;ManifestSha256=$digest
        OnlySynthetic=$true;OutlookOrPstFilesAccessed=$false
        DiskJournalOrClaimWritten=$false;HistoricMoveClaimReused=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Assert-OPA265BW4k7uSyntheticSuite {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Suite)
    if([string]$Suite.Schema -cne '2.6.5-BW4k7u.SyntheticMultiItemSuite.1' -or
       -not [bool]$Suite.OnlySynthetic -or
       [bool]$Suite.OutlookOrPstFilesAccessed -or
       [bool]$Suite.DiskJournalOrClaimWritten -or
       [bool]$Suite.HistoricMoveClaimReused -or
       [bool]$Suite.WriterPermit -or [bool]$Suite.ProductionReady){
        throw 'BW4k7u requires exact no-writer synthetic suite.'
    }
    $g=[guid]::Empty
    if(-not [guid]::TryParse([string]$Suite.SuiteId,[ref]$g) -or
       $g -eq [guid]::Empty -or [string]$Suite.SuiteId -cne $g.ToString('D')){
        throw 'BW4k7u SuiteId invalid.'
    }
    $items=@($Suite.Cases)
    if($items.Count -ne 12 -or [int]$Suite.FixtureCount -ne 12){
        throw 'BW4k7u exactly 12 synthetic fixtures required.'
    }
    $expect=New-OPA265BW4k7uSyntheticSuite -SuiteId ([string]$Suite.SuiteId)
    $hash=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $items -Depth 12 -Compress)
    if([string]$Suite.ManifestSha256 -cne [string]$expect.ManifestSha256 -or
       $hash -cne [string]$expect.ManifestSha256){
        throw 'BW4k7u synthetic manifest or fixture contents modified.'
    }
    return $true
}
function Get-OPA265BW4k7uSyntheticCapacityPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Suite,
          [ValidateRange(1990,2101)][int]$ArchiveBeforeYear=2026,
          [ValidateRange(0,1099511627776)][long]$SimulatedSegmentCapBytes=0,
          [ValidateRange(104857600,1099511627776)][long]$MaxArchivePstSizeBytes=45000000000,
          [ValidateRange(0,1099511627775)][long]$SafetyMarginBytes=3000000000)
    [void](Assert-OPA265BW4k7uSyntheticSuite -Suite $Suite)
    $capacity=Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes $MaxArchivePstSizeBytes -SafetyMarginBytes $SafetyMarginBytes -EstimatedExpansionPct 25 -PerMessageOverheadBytes 65536
    $usable=[long]$capacity.UsableEstimatedPayloadBytes
    if($SimulatedSegmentCapBytes -ne 0){
        if($SimulatedSegmentCapBytes -lt 65536 -or $SimulatedSegmentCapBytes -gt $usable){
            throw 'BW4k7u artificial rollover cap must be between 65536 and safe capacity.'
        }
        $usable=$SimulatedSegmentCapBytes
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $preserved=New-Object 'System.Collections.Generic.List[object]'
    $used=@{}
    foreach($c in @($Suite.Cases | Sort-Object Year,Name)){
        $eligible=([bool]$c.EligibleForArchive -and [int]$c.Class -eq 43 -and
          [int]$c.Year -lt $ArchiveBeforeYear)
        if(-not $eligible){
            $reason=if([int]$c.Class -ne 43){'NonMailPreservedRequiresClassSpecificProof'}
                    elseif([int]$c.Year -ge $ArchiveBeforeYear){'CurrentYearRetained'}
                    else{'FixtureNotEligible'}
            $preserved.Add([pscustomobject]@{
                CaseId=[string]$c.CaseId;Name=[string]$c.Name
                Year=[int]$c.Year;Kind=[string]$c.Kind
                Reason=$reason;SyntheticSourceStillContainsObject=$true
            })
            continue
        }
        $forecast=[long]([decimal]::Ceiling([decimal][long]$c.LogicalSizeBytes*([decimal]125/[decimal]100))+65536M)
        if($forecast -gt $usable){throw ('BW4k7u modeled message larger than segment: '+$c.Name)}
        $key=[string]$c.Year
        if(-not $used.ContainsKey($key)){$used[$key]=[pscustomobject]@{Segment=1;Bytes=0L}}
        $u=$used[$key]
        if(([long]$u.Bytes+$forecast) -gt $usable){
            $u.Segment=[int]$u.Segment+1
            if($u.Segment -gt 999){throw 'BW4k7u too many synthetic PST segments.'}
            $u.Bytes=0L
        }
        $u.Bytes=[long]$u.Bytes+$forecast
        $suffix=if($u.Segment -eq 1){''}else{('-{0:D2}' -f $u.Segment)}
        $rows.Add([pscustomobject][ordered]@{
            CaseId=[string]$c.CaseId;Name=[string]$c.Name
            Year=[int]$c.Year;Role=[string]$c.Role
            OriginalFolderPath=[string]$c.SourceFolderPath
            ArchiveFolderPath=[string]$c.SourceFolderPath
            ArchivePstFileName=('info@stios.ru.Archive-'+$c.Year+$suffix+'.pst')
            SegmentNumber=[int]$u.Segment
            EstimatedItemBytes=$forecast
            EstimatedCurrentSegmentBytes=[long]$u.Bytes
            SyntheticOnly=$true
            PhysicalDestinationPstCreated=$false
        })
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticCapacityPlan.1'
        SuiteId=[string]$Suite.SuiteId
        ArchiveBeforeYear=$ArchiveBeforeYear
        PlannedMaxPstBytes=[long]$capacity.MaxArchivePstSizeBytes
        PlannedSafetyMarginBytes=[long]$capacity.SafetyMarginBytes
        EffectiveSimulatedSegmentBytes=$usable
        ArtificialRolloverCapUsed=($SimulatedSegmentCapBytes -ne 0)
        Allocations=@($rows.ToArray());PreservedObjects=@($preserved.ToArray())
        FolderHierarchyRemainsUnchanged=$true
        RealPstCreated=$false;OutlookMoveAllowed=$false;ProductionReady=$false
    }
}
function New-OPA265BW4k7uSyntheticLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Suite,
          [Parameter(Mandatory=$true)][object]$CapacityPlan)
    [void](Assert-OPA265BW4k7uSyntheticSuite -Suite $Suite)
    if([string]$CapacityPlan.Schema -cne '2.6.5-BW4k7u.SyntheticCapacityPlan.1' -or
       [string]$CapacityPlan.SuiteId -cne [string]$Suite.SuiteId -or
       [bool]$CapacityPlan.RealPstCreated -or
       [bool]$CapacityPlan.OutlookMoveAllowed -or
       [bool]$CapacityPlan.ProductionReady){
        throw 'BW4k7u capacity plan wrong suite or unsafe.'
    }
    $a=@($CapacityPlan.Allocations)
    if($a.Count -ne @($Suite.Cases | Where-Object {$_.EligibleForArchive -and $_.Class -eq 43 -and $_.Year -lt [int]$CapacityPlan.ArchiveBeforeYear}).Count -or
       ($a.Count+@($CapacityPlan.PreservedObjects).Count) -ne 12){
        throw 'BW4k7u per-year allocation and preserved fixture counts do not reconcile.'
    }
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($slot in $a){
        $item=@($Suite.Cases | Where-Object {$_.CaseId -ceq $slot.CaseId})
        if($item.Count -ne 1 -or -not $seen.Add([string]$slot.CaseId) -or
           -not [bool]$item[0].EligibleForArchive -or
           [int]$slot.Year -ne [int]$item[0].Year -or
           [string]$slot.OriginalFolderPath -cne [string]$item[0].SourceFolderPath -or
           [string]$slot.ArchiveFolderPath -cne [string]$item[0].SourceFolderPath){
            throw 'BW4k7u invalid duplicated or modified folder/year allocation.'
        }
        $allowedFilePattern='^info@stios[.]ru[.]Archive-'+[string]$item[0].Year+'(?:-[0-9]{2,3})?[.]pst
            DestinationPst=[string]$slot.ArchivePstFileName
            State='UnclaimedSourceOnly'
            IntentPinnedInMemory=$false;ClaimPinnedInMemory=$false
            ModelAttemptCount=0;SourceExists=$true;DestinationExists=$false
            OriginalFixture=(Copy-OPA265BW4k7uObject -Value $item[0])
            DestinationFixture=$null
            IndependentlyReviewed=$false
        })
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticLedger.1'
        SuiteId=[string]$Suite.SuiteId
        Suite=$Suite;CapacityPlan=$CapacityPlan
        SuiteManifestSha256=[string]$Suite.ManifestSha256
        Rows=@($rows.ToArray())
        BatchStatus='FreshSyntheticBatch'
        Interrupted=$false;LastFault='None'
        OnlyInMemorySynthetic=$true
        PhysicalCrashOrResumeProven=$false
        DiskJournalOrClaimCreated=$false
        OutlookOrPstAccessed=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7uRow {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [Parameter(Mandatory=$true)][string]$CaseId)
    if([string]$Ledger.Schema -cne '2.6.5-BW4k7u.SyntheticLedger.1' -or
       -not [bool]$Ledger.OnlyInMemorySynthetic -or
       [bool]$Ledger.DiskJournalOrClaimCreated -or
       [bool]$Ledger.OutlookOrPstAccessed -or
       [bool]$Ledger.AutomaticRetryAllowed -or
       [bool]$Ledger.WriterPermit -or [bool]$Ledger.ProductionReady){
        throw 'BW4k7u ledger not safe synthetic only.'
    }
    [void](Assert-OPA265BW4k7uSyntheticSuite -Suite $Ledger.Suite)
    if([string]$Ledger.SuiteManifestSha256 -cne [string]$Ledger.Suite.ManifestSha256){
        throw 'BW4k7u ledger manifest identity not pinned.'
    }
    $r=@($Ledger.Rows | Where-Object {$_.CaseId -ceq $CaseId})
    $expected=@($Ledger.Suite.Cases | Where-Object {$_.CaseId -ceq $CaseId})
    if($r.Count -ne 1 -or $expected.Count -ne 1){
        throw 'BW4k7u duplicate or wrong synthetic CaseId.'
    }
    $x=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $r[0].OriginalFixture -Depth 12 -Compress)
    $y=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $expected[0] -Depth 12 -Compress)
    if($x -cne $y){throw 'BW4k7u original synthetic item mutated after manifest pin.'}
    return $r[0]
}
function Compare-OPA265BW4k7uSyntheticWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    if($null -eq $Before -or $null -eq $After -or
       [string]$Before.Schema -cne '2.6.5-BW4k7u.SyntheticCase.1' -or
       [string]$After.Schema -cne '2.6.5-BW4k7u.SyntheticCase.1' -or
       [string]$Before.Kind -cne 'Mail' -or
       -not [bool]$Before.SyntheticOnly -or -not [bool]$After.SyntheticOnly -or
       [bool]$Before.OutlookMAPIObserved -or [bool]$After.OutlookMAPIObserved){
        throw 'BW4k7u comparison only supports synthetic Mail cases.'
    }
    $different=New-Object 'System.Collections.Generic.List[string]'
    $fields=@('SuiteId','CaseId','Name','Kind','Class','MessageClass','Role',
        'SourceFolderPath','Year','Subject','Sender','RecipientsTo','RecipientsCc',
        'RecipientsBcc','Body','HtmlBody','TransportHeaders','ReceivedUtcTicks',
        'SentUtcTicks','ReadState','Categories','FollowupFlag',
        'SourceEntryId','DestinationEntryId')
    foreach($name in $fields){
        $x=ConvertTo-Json -InputObject $Before.$name -Depth 6 -Compress
        $y=ConvertTo-Json -InputObject $After.$name -Depth 6 -Compress
        if($x -cne $y){$different.Add($name)}
    }
    $aa=@($Before.Attachments);$bb=@($After.Attachments)
    $attachmentsMatch=($aa.Count -eq $bb.Count)
    foreach($att in @($aa)+@($bb)){
        $raw=[Convert]::FromBase64String([string]$att.BytesBase64)
        if([int]$att.ByteCount -ne $raw.Length -or
           (Get-OPA265BW4k7uByteHash -Bytes $raw) -cne [string]$att.PayloadSha256){
            $attachmentsMatch=$false
        }
    }
    if($attachmentsMatch){
        for($i=0;$i -lt $aa.Count;$i++){
            if([string]$aa[$i].Name -cne [string]$bb[$i].Name -or
               [int]$aa[$i].ByteCount -ne [int]$bb[$i].ByteCount -or
               [string]$aa[$i].PayloadSha256 -cne [string]$bb[$i].PayloadSha256){
                $attachmentsMatch=$false
            }
        }
    }
    $semantic=($different.Count -eq 0 -and $attachmentsMatch)
    $req=[pscustomobject]@{
        CaseId=[string]$Before.CaseId;Kind='Mail';MessageClass='IPM.Note'
        PreMoveSourceCount=1;PreMoveDestinationCount=0
        PostMoveSourceCount=0;PostMoveDestinationCount=1
        BeforeRawMessageFlags=[long]$Before.BeforeRawMessageFlags
        AfterRawMessageFlags=[long]$After.AfterRawMessageFlags
        MailItemSizeBefore=[long]$Before.LogicalSizeBytes
        MailItemSizeAfter=[long]($After.LogicalSizeBytes+$After.ModeledSizeDeltaBytes)
        ExactSourceAndDestinationStoresVerified=$true
        ImmutableIntentAndClaimPinned=$true;SingleAttemptClaimVerified=$true
        UniqueMessageCorrelationVerified=$true
        OriginalAndDestinationClassMatch=($different -notcontains 'Class' -and $different -notcontains 'MessageClass')
        SubjectMatched=($different -notcontains 'Subject')
        SenderMatched=($different -notcontains 'Sender')
        RecipientSetMatched=($different -notcontains 'RecipientsTo' -and $different -notcontains 'RecipientsCc' -and $different -notcontains 'RecipientsBcc')
        TextBodyMatched=($different -notcontains 'Body')
        HtmlBodyMatchedOrProvenAbsent=($different -notcontains 'HtmlBody')
        TransportHeadersMatchedOrProvenAbsent=($different -notcontains 'TransportHeaders')
        SentAndReceivedTimesMatched=($different -notcontains 'SentUtcTicks' -and $different -notcontains 'ReceivedUtcTicks')
        AttachmentCountAndOrderMatched=$attachmentsMatch
        AttachmentPayloadSha256Matched=$attachmentsMatch
        ReadUnreadAndProtectedFlagsMatched=($different -notcontains 'ReadState')
        CategoriesAndFollowupMatched=($different -notcontains 'Categories' -and $different -notcontains 'FollowupFlag')
        OutlookRestartReadbackMatched=$true;IndependentReadbackSucceeded=$true
    }
    $result=Test-OPA265BW4k7tSemanticCase -Case $req
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticSemanticWitness.1'
        CaseId=[string]$Before.CaseId
        SemanticFieldsMatched=$semantic
        DifferentFields=@($different.ToArray())
        ExactAttachmentBytesAndSha256Matched=$attachmentsMatch
        ModeledMailItemSizeDelta=[long]$result.MailItemSizeDeltaBytes
        ProspectivePolicyCategory=[string]$result.Category
        Undocumented0x00010000Changed=[bool]$result.Undocumented0x00010000Changed
        ProspectiveSemanticPolicy=$result
        RealOutlookPostMoveProof=$false;OperatorResidualRiskAccepted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Set-OPA265BW4k7uSyntheticPhase {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [Parameter(Mandatory=$true)][string]$CaseId,
          [Parameter(Mandatory=$true)][ValidateSet('Intent','Claim','ModelMove','Reconcile')][string]$Phase)
    $r=Get-OPA265BW4k7uRow -Ledger $Ledger -CaseId $CaseId
    switch($Phase){
        'Intent'{
            if($r.State -cne 'UnclaimedSourceOnly'){throw 'BW4k7u intent duplicate or replay.'}
            $r.IntentPinnedInMemory=$true;$r.State='ModeledIntentNoDiskClaim'
        }
        'Claim'{
            if($r.State -cne 'ModeledIntentNoDiskClaim' -or
               -not $r.IntentPinnedInMemory -or $r.ClaimPinnedInMemory){
                throw 'BW4k7u duplicate claim or missing intent.'
            }
            $r.ClaimPinnedInMemory=$true;$r.ModelAttemptCount=1
            $r.State='ClaimedSourcePresentNeverRetryAutomatically'
        }
        'ModelMove'{
            if($r.State -cne 'ClaimedSourcePresentNeverRetryAutomatically' -or
               -not $r.SourceExists -or $r.DestinationExists -or
               [int]$r.ModelAttemptCount -ne 1){
                throw 'BW4k7u modeled Move cannot replay a claimed message.'
            }
            $r.DestinationFixture=Copy-OPA265BW4k7uObject -Value $r.OriginalFixture
            $r.SourceExists=$false;$r.DestinationExists=$true
            $r.State='DestinationOnlyAwaitIndependentReconciliation'
        }
        'Reconcile'{
            if($r.State -cnotin @('ClaimedSourcePresentNeverRetryAutomatically','DestinationOnlyAwaitIndependentReconciliation')){
                throw 'BW4k7u cannot reconcile unclaimed, duplicate or previously reconciled case.'
            }
            if($r.SourceExists -and -not $r.DestinationExists){
                $r.State='ManualReviewClaimedSourceStillPresentNoRetry'
            }elseif($r.DestinationExists -and -not $r.SourceExists){
                $check=Compare-OPA265BW4k7uSyntheticWitness -Before $r.OriginalFixture -After $r.DestinationFixture
                if($check.SemanticFieldsMatched){
                    $r.State='SyntheticReconciledRiskReviewOnly'
                }else{
                    $r.State='BlockedSemanticMismatchNeverRetry'
                }
            }else{$r.State='BlockedAmbiguousSourceDestinationNeverRetry'}
            $r.IndependentlyReviewed=$true
        }
    }
    return [pscustomobject]@{
        CaseId=$CaseId;Phase=$Phase
        State=[string]$r.State
        AttemptCount=[int]$r.ModelAttemptCount
        DurableClaimWritten=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7uSyntheticRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger)
    if([string]$Ledger.Schema -cne '2.6.5-BW4k7u.SyntheticLedger.1' -or
       -not [bool]$Ledger.OnlyInMemorySynthetic -or
       [bool]$Ledger.DiskJournalOrClaimCreated -or [bool]$Ledger.OutlookOrPstAccessed){
        throw 'BW4k7u read-only recovery requires isolated in-memory ledger.'
    }
    $states=@{};$n=0L;$claims=0;$pending=0;$manual=0
    foreach($r in @($Ledger.Rows)){
        [void](Get-OPA265BW4k7uRow -Ledger $Ledger -CaseId ([string]$r.CaseId))
        $key=[string]$r.State
        if(-not $states.ContainsKey($key)){$states[$key]=0}
        $states[$key]++
        $n+=[long]$r.ModelAttemptCount
        if($r.ClaimPinnedInMemory){$claims++}
        if($key -eq 'UnclaimedSourceOnly'){$pending++}
        if($key -match 'ManualReview|Blocked|Await|ClaimedSourcePresent'){$manual++}
    }
    $all=($manual -eq 0 -and $pending -eq 0 -and
       @($Ledger.Rows | Where-Object {$_.State -cne 'SyntheticReconciledRiskReviewOnly'}).Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticRecovery.1'
        SuiteId=[string]$Ledger.SuiteId
        ModelAttemptCount=$n;ModeledClaimCount=$claims
        PendingUnclaimedCount=$pending;ManualReviewCount=$manual
        States=$states
        AllEightSyntheticMailCasesReconciled=$all
        ResumeOrRetryAutomaticallyAllowed=$false
        ClaimedSourceCannotBeReplayed=$true
        OriginalSourcePstUntouched=$true
        InMemoryOnlyNoDurableClaim=$true
        ActualCrashOrRestartRecoveryProven=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Invoke-OPA265BW4k7uSyntheticBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [ValidateSet('None','AfterIntent','AfterClaim','AfterMove')][string]$FaultPoint='None',
          [string]$FaultCaseId='')
    if($Ledger.Interrupted -or $Ledger.BatchStatus -cne 'FreshSyntheticBatch' -or
       @($Ledger.Rows | Where-Object {$_.State -cne 'UnclaimedSourceOnly'}).Count -ne 0){
        throw 'BW4k7u no automatic replay/resume of a non-fresh synthetic batch.'
    }
    if($FaultPoint -cne 'None' -and
       @($Ledger.Rows | Where-Object {$_.CaseId -ceq $FaultCaseId}).Count -ne 1){
        throw 'BW4k7u injected fault must name one exact synthetic eligible CaseId.'
    }
    $Ledger.BatchStatus='SyntheticBatchRunning'
    foreach($r in @($Ledger.Rows)){
        $id=[string]$r.CaseId
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Intent)
        if($FaultPoint -eq 'AfterIntent' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterIntent';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Claim)
        if($FaultPoint -eq 'AfterClaim' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterClaim';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase ModelMove)
        if($FaultPoint -eq 'AfterMove' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterMove';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Reconcile)
    }
    $Ledger.BatchStatus=if($Ledger.Interrupted){'InterruptedNoAutomaticResume'}
                          else{'SyntheticBatchFinishedNoRealMove'}
    return (Get-OPA265BW4k7uSyntheticRecovery -Ledger $Ledger)
}

        if([string]$slot.ArchivePstFileName -cnotmatch $allowedFilePattern -or
           [int]$slot.SegmentNumber -lt 1 -or [int]$slot.SegmentNumber -gt 999){
            throw 'BW4k7u unsafe archive file segment or year naming.'
        }
        $rows.Add([pscustomobject][ordered]@{
            CaseId=[string]$slot.CaseId
            DestinationPst=[string]$slot.ArchivePstFileName
            State='UnclaimedSourceOnly'
            IntentPinnedInMemory=$false;ClaimPinnedInMemory=$false
            ModelAttemptCount=0;SourceExists=$true;DestinationExists=$false
            OriginalFixture=(Copy-OPA265BW4k7uObject -Value $item[0])
            DestinationFixture=$null
            IndependentlyReviewed=$false
        })
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticLedger.1'
        SuiteId=[string]$Suite.SuiteId
        Suite=$Suite;CapacityPlan=$CapacityPlan
        SuiteManifestSha256=[string]$Suite.ManifestSha256
        Rows=@($rows.ToArray())
        BatchStatus='FreshSyntheticBatch'
        Interrupted=$false;LastFault='None'
        OnlyInMemorySynthetic=$true
        PhysicalCrashOrResumeProven=$false
        DiskJournalOrClaimCreated=$false
        OutlookOrPstAccessed=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7uRow {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [Parameter(Mandatory=$true)][string]$CaseId)
    if([string]$Ledger.Schema -cne '2.6.5-BW4k7u.SyntheticLedger.1' -or
       -not [bool]$Ledger.OnlyInMemorySynthetic -or
       [bool]$Ledger.DiskJournalOrClaimCreated -or
       [bool]$Ledger.OutlookOrPstAccessed -or
       [bool]$Ledger.AutomaticRetryAllowed -or
       [bool]$Ledger.WriterPermit -or [bool]$Ledger.ProductionReady){
        throw 'BW4k7u ledger not safe synthetic only.'
    }
    [void](Assert-OPA265BW4k7uSyntheticSuite -Suite $Ledger.Suite)
    if([string]$Ledger.SuiteManifestSha256 -cne [string]$Ledger.Suite.ManifestSha256){
        throw 'BW4k7u ledger manifest identity not pinned.'
    }
    $r=@($Ledger.Rows | Where-Object {$_.CaseId -ceq $CaseId})
    $expected=@($Ledger.Suite.Cases | Where-Object {$_.CaseId -ceq $CaseId})
    if($r.Count -ne 1 -or $expected.Count -ne 1){
        throw 'BW4k7u duplicate or wrong synthetic CaseId.'
    }
    $x=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $r[0].OriginalFixture -Depth 12 -Compress)
    $y=Get-OPA265BW4k7uHash -Text (ConvertTo-Json -InputObject $expected[0] -Depth 12 -Compress)
    if($x -cne $y){throw 'BW4k7u original synthetic item mutated after manifest pin.'}
    return $r[0]
}
function Compare-OPA265BW4k7uSyntheticWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    if($null -eq $Before -or $null -eq $After -or
       [string]$Before.Schema -cne '2.6.5-BW4k7u.SyntheticCase.1' -or
       [string]$After.Schema -cne '2.6.5-BW4k7u.SyntheticCase.1' -or
       [string]$Before.Kind -cne 'Mail' -or
       -not [bool]$Before.SyntheticOnly -or -not [bool]$After.SyntheticOnly -or
       [bool]$Before.OutlookMAPIObserved -or [bool]$After.OutlookMAPIObserved){
        throw 'BW4k7u comparison only supports synthetic Mail cases.'
    }
    $different=New-Object 'System.Collections.Generic.List[string]'
    $fields=@('SuiteId','CaseId','Name','Kind','Class','MessageClass','Role',
        'SourceFolderPath','Year','Subject','Sender','RecipientsTo','RecipientsCc',
        'RecipientsBcc','Body','HtmlBody','TransportHeaders','ReceivedUtcTicks',
        'SentUtcTicks','ReadState','Categories','FollowupFlag',
        'SourceEntryId','DestinationEntryId')
    foreach($name in $fields){
        $x=ConvertTo-Json -InputObject $Before.$name -Depth 6 -Compress
        $y=ConvertTo-Json -InputObject $After.$name -Depth 6 -Compress
        if($x -cne $y){$different.Add($name)}
    }
    $aa=@($Before.Attachments);$bb=@($After.Attachments)
    $attachmentsMatch=($aa.Count -eq $bb.Count)
    foreach($att in @($aa)+@($bb)){
        $raw=[Convert]::FromBase64String([string]$att.BytesBase64)
        if([int]$att.ByteCount -ne $raw.Length -or
           (Get-OPA265BW4k7uByteHash -Bytes $raw) -cne [string]$att.PayloadSha256){
            $attachmentsMatch=$false
        }
    }
    if($attachmentsMatch){
        for($i=0;$i -lt $aa.Count;$i++){
            if([string]$aa[$i].Name -cne [string]$bb[$i].Name -or
               [int]$aa[$i].ByteCount -ne [int]$bb[$i].ByteCount -or
               [string]$aa[$i].PayloadSha256 -cne [string]$bb[$i].PayloadSha256){
                $attachmentsMatch=$false
            }
        }
    }
    $semantic=($different.Count -eq 0 -and $attachmentsMatch)
    $req=[pscustomobject]@{
        CaseId=[string]$Before.CaseId;Kind='Mail';MessageClass='IPM.Note'
        PreMoveSourceCount=1;PreMoveDestinationCount=0
        PostMoveSourceCount=0;PostMoveDestinationCount=1
        BeforeRawMessageFlags=[long]$Before.BeforeRawMessageFlags
        AfterRawMessageFlags=[long]$After.AfterRawMessageFlags
        MailItemSizeBefore=[long]$Before.LogicalSizeBytes
        MailItemSizeAfter=[long]($After.LogicalSizeBytes+$After.ModeledSizeDeltaBytes)
        ExactSourceAndDestinationStoresVerified=$true
        ImmutableIntentAndClaimPinned=$true;SingleAttemptClaimVerified=$true
        UniqueMessageCorrelationVerified=$true
        OriginalAndDestinationClassMatch=($different -notcontains 'Class' -and $different -notcontains 'MessageClass')
        SubjectMatched=($different -notcontains 'Subject')
        SenderMatched=($different -notcontains 'Sender')
        RecipientSetMatched=($different -notcontains 'RecipientsTo' -and $different -notcontains 'RecipientsCc' -and $different -notcontains 'RecipientsBcc')
        TextBodyMatched=($different -notcontains 'Body')
        HtmlBodyMatchedOrProvenAbsent=($different -notcontains 'HtmlBody')
        TransportHeadersMatchedOrProvenAbsent=($different -notcontains 'TransportHeaders')
        SentAndReceivedTimesMatched=($different -notcontains 'SentUtcTicks' -and $different -notcontains 'ReceivedUtcTicks')
        AttachmentCountAndOrderMatched=$attachmentsMatch
        AttachmentPayloadSha256Matched=$attachmentsMatch
        ReadUnreadAndProtectedFlagsMatched=($different -notcontains 'ReadState')
        CategoriesAndFollowupMatched=($different -notcontains 'Categories' -and $different -notcontains 'FollowupFlag')
        OutlookRestartReadbackMatched=$true;IndependentReadbackSucceeded=$true
    }
    $result=Test-OPA265BW4k7tSemanticCase -Case $req
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticSemanticWitness.1'
        CaseId=[string]$Before.CaseId
        SemanticFieldsMatched=$semantic
        DifferentFields=@($different.ToArray())
        ExactAttachmentBytesAndSha256Matched=$attachmentsMatch
        ModeledMailItemSizeDelta=[long]$result.MailItemSizeDeltaBytes
        ProspectivePolicyCategory=[string]$result.Category
        Undocumented0x00010000Changed=[bool]$result.Undocumented0x00010000Changed
        ProspectiveSemanticPolicy=$result
        RealOutlookPostMoveProof=$false;OperatorResidualRiskAccepted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Set-OPA265BW4k7uSyntheticPhase {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [Parameter(Mandatory=$true)][string]$CaseId,
          [Parameter(Mandatory=$true)][ValidateSet('Intent','Claim','ModelMove','Reconcile')][string]$Phase)
    $r=Get-OPA265BW4k7uRow -Ledger $Ledger -CaseId $CaseId
    switch($Phase){
        'Intent'{
            if($r.State -cne 'UnclaimedSourceOnly'){throw 'BW4k7u intent duplicate or replay.'}
            $r.IntentPinnedInMemory=$true;$r.State='ModeledIntentNoDiskClaim'
        }
        'Claim'{
            if($r.State -cne 'ModeledIntentNoDiskClaim' -or
               -not $r.IntentPinnedInMemory -or $r.ClaimPinnedInMemory){
                throw 'BW4k7u duplicate claim or missing intent.'
            }
            $r.ClaimPinnedInMemory=$true;$r.ModelAttemptCount=1
            $r.State='ClaimedSourcePresentNeverRetryAutomatically'
        }
        'ModelMove'{
            if($r.State -cne 'ClaimedSourcePresentNeverRetryAutomatically' -or
               -not $r.SourceExists -or $r.DestinationExists -or
               [int]$r.ModelAttemptCount -ne 1){
                throw 'BW4k7u modeled Move cannot replay a claimed message.'
            }
            $r.DestinationFixture=Copy-OPA265BW4k7uObject -Value $r.OriginalFixture
            $r.SourceExists=$false;$r.DestinationExists=$true
            $r.State='DestinationOnlyAwaitIndependentReconciliation'
        }
        'Reconcile'{
            if($r.State -cnotin @('ClaimedSourcePresentNeverRetryAutomatically','DestinationOnlyAwaitIndependentReconciliation')){
                throw 'BW4k7u cannot reconcile unclaimed, duplicate or previously reconciled case.'
            }
            if($r.SourceExists -and -not $r.DestinationExists){
                $r.State='ManualReviewClaimedSourceStillPresentNoRetry'
            }elseif($r.DestinationExists -and -not $r.SourceExists){
                $check=Compare-OPA265BW4k7uSyntheticWitness -Before $r.OriginalFixture -After $r.DestinationFixture
                if($check.SemanticFieldsMatched){
                    $r.State='SyntheticReconciledRiskReviewOnly'
                }else{
                    $r.State='BlockedSemanticMismatchNeverRetry'
                }
            }else{$r.State='BlockedAmbiguousSourceDestinationNeverRetry'}
            $r.IndependentlyReviewed=$true
        }
    }
    return [pscustomobject]@{
        CaseId=$CaseId;Phase=$Phase
        State=[string]$r.State
        AttemptCount=[int]$r.ModelAttemptCount
        DurableClaimWritten=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7uSyntheticRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger)
    if([string]$Ledger.Schema -cne '2.6.5-BW4k7u.SyntheticLedger.1' -or
       -not [bool]$Ledger.OnlyInMemorySynthetic -or
       [bool]$Ledger.DiskJournalOrClaimCreated -or [bool]$Ledger.OutlookOrPstAccessed){
        throw 'BW4k7u read-only recovery requires isolated in-memory ledger.'
    }
    $states=@{};$n=0L;$claims=0;$pending=0;$manual=0
    foreach($r in @($Ledger.Rows)){
        [void](Get-OPA265BW4k7uRow -Ledger $Ledger -CaseId ([string]$r.CaseId))
        $key=[string]$r.State
        if(-not $states.ContainsKey($key)){$states[$key]=0}
        $states[$key]++
        $n+=[long]$r.ModelAttemptCount
        if($r.ClaimPinnedInMemory){$claims++}
        if($key -eq 'UnclaimedSourceOnly'){$pending++}
        if($key -match 'ManualReview|Blocked|Await|ClaimedSourcePresent'){$manual++}
    }
    $all=($manual -eq 0 -and $pending -eq 0 -and
       @($Ledger.Rows | Where-Object {$_.State -cne 'SyntheticReconciledRiskReviewOnly'}).Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7u.SyntheticRecovery.1'
        SuiteId=[string]$Ledger.SuiteId
        ModelAttemptCount=$n;ModeledClaimCount=$claims
        PendingUnclaimedCount=$pending;ManualReviewCount=$manual
        States=$states
        AllEightSyntheticMailCasesReconciled=$all
        ResumeOrRetryAutomaticallyAllowed=$false
        ClaimedSourceCannotBeReplayed=$true
        OriginalSourcePstUntouched=$true
        InMemoryOnlyNoDurableClaim=$true
        ActualCrashOrRestartRecoveryProven=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Invoke-OPA265BW4k7uSyntheticBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ledger,
          [ValidateSet('None','AfterIntent','AfterClaim','AfterMove')][string]$FaultPoint='None',
          [string]$FaultCaseId='')
    if($Ledger.Interrupted -or $Ledger.BatchStatus -cne 'FreshSyntheticBatch' -or
       @($Ledger.Rows | Where-Object {$_.State -cne 'UnclaimedSourceOnly'}).Count -ne 0){
        throw 'BW4k7u no automatic replay/resume of a non-fresh synthetic batch.'
    }
    if($FaultPoint -cne 'None' -and
       @($Ledger.Rows | Where-Object {$_.CaseId -ceq $FaultCaseId}).Count -ne 1){
        throw 'BW4k7u injected fault must name one exact synthetic eligible CaseId.'
    }
    $Ledger.BatchStatus='SyntheticBatchRunning'
    foreach($r in @($Ledger.Rows)){
        $id=[string]$r.CaseId
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Intent)
        if($FaultPoint -eq 'AfterIntent' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterIntent';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Claim)
        if($FaultPoint -eq 'AfterClaim' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterClaim';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase ModelMove)
        if($FaultPoint -eq 'AfterMove' -and $FaultCaseId -ceq $id){
            $Ledger.Interrupted=$true;$Ledger.LastFault='AfterMove';break
        }
        [void](Set-OPA265BW4k7uSyntheticPhase -Ledger $Ledger -CaseId $id -Phase Reconcile)
    }
    $Ledger.BatchStatus=if($Ledger.Interrupted){'InterruptedNoAutomaticResume'}
                          else{'SyntheticBatchFinishedNoRealMove'}
    return (Get-OPA265BW4k7uSyntheticRecovery -Ledger $Ledger)
}
