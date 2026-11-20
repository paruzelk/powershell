#requires -Version 5.1
# ARCH3v real operator TEST PST exactly-ten source full semantic evidence only.
# Original ARCH3u Plan/Inventory, original ARCH2b SHA256 attachments,
# original ARCH3d canonical witness digest, original ARCH3c CreateNew/Flush(true),
# original ARCH3i protected-ACL directory. No PST/Journal/Index/Move writer.
. (Join-Path $PSScriptRoot 'ARCH3uRealBatchTenPreflight.ps1')
. (Join-Path $PSScriptRoot 'ARCH3iSealedFullOriginalWitness.ps1')

function Get-OPA265ARCH3vEvidenceLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    $parent=Get-OPA265ARCH3iEvidenceLayout -RunId $RunId
    $dir=Join-Path ([string]$parent.LocalAppData) ('OPA265-ARCH3v-'+$RunId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3v.EvidenceLayout.1'
        RunId=$RunId;Root=$dir
        WitnessPath=(Join-Path $dir 'original-ten-full-semantic-witness.json')
    }
}

function Assert-OPA265ARCH3vExactPins {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$ExpectedPreviewSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedSourceStoreIdSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedOriginalIndexSha256,
          [Parameter(Mandatory=$true)][long]$ExpectedSourcePstLengthBytes)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId){throw 'ARCH3v requires exact canonical lowercase RunId.'}
    foreach($h in @($ExpectedPreviewSha256,$ExpectedSourceStoreIdSha256,$ExpectedOriginalIndexSha256)){
        if($h -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3v requires three canonical externally observed SHA256 pins.'}
    }
    if($ExpectedSourcePstLengthBytes -le 0){throw 'ARCH3v requires exact observed source PST byte length.'}
    return $true
}

function Get-OPA265ARCH3vAuditDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Envelope)
    if([string]$Envelope.Schema -cne '2.6.5-ARCH3v.OriginalTenFullWitnessEnvelope.1' -or
       [int]$Envelope.BatchSize -ne 10 -or
       [string]$Envelope.SourcePst -cnotmatch '(?i)info@stios\.ru\.pst$' -or
       [string]$Envelope.PreviewSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Envelope.OriginalIndexSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Envelope.SourceStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [long]$Envelope.SourcePstLengthBytes -le 0 -or
       [int]$Envelope.ArchiveYear -ne 2020 -or
       [int]$Envelope.ArchivePart -ne 3 -or
       [string]$Envelope.TargetPstPreview -cnotmatch '(?i)info@stios\.ru\.Archive-2020-03\.pst$' -or
       [bool]$Envelope.RealMailMovePerformed -or
       [bool]$Envelope.OriginalOperationJournalWritten -or
       [bool]$Envelope.OriginalDuplicateIndexWritten -or
       [bool]$Envelope.ArchivePstCreated -or
       [bool]$Envelope.WriterPermit -or [bool]$Envelope.ProductionReady){
        throw 'ARCH3v sealed original real source provenance or writer flags invalid.'
    }
    $validRun=[guid]::Empty
    if(-not [guid]::TryParse([string]$Envelope.RunId,[ref]$validRun) -or
       $validRun -eq [guid]::Empty -or $validRun.ToString('D') -cne [string]$Envelope.RunId){
        throw 'ARCH3v envelope has invalid RunId.'
    }
    $rows=@($Envelope.Rows)
    if($rows.Count -ne 10){throw 'ARCH3v requires exactly ten FULL original semantic witnesses.'}
    $parts=New-Object 'System.Collections.Generic.List[object]'
    foreach($v in @('2.6.5-ARCH3v.OriginalTenFullWitnessEnvelope.1',
         [string]$Envelope.RunId,[string]$Envelope.SourcePst,[string]$Envelope.PreviewSha256,
         [string]$Envelope.SourceStoreIdSha256,[string]$Envelope.OriginalIndexSha256,
         [string]$Envelope.SourcePstLengthBytes,[string]$Envelope.ArchiveYear,
         [string]$Envelope.ArchivePart,[string]$Envelope.TargetPstPreview)){
        [void]$parts.Add($v)
    }
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $contracts=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $totalAttachments=0
    for($i=0;$i -lt 10;$i++){
        $r=$rows[$i]
        if($null -eq $r -or
           [int]$r.Ordinal -ne ($i+1) -or
           [string]$r.SourceEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
           -not $ids.Add([string]$r.SourceEntryId) -or
           [string]$r.OriginalContractSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           -not $contracts.Add([string]$r.OriginalContractSha256) -or
           [string]$r.OriginalOperationId -cne ('ARCH3b-'+[string]$r.OriginalContractSha256) -or
           [string]$r.TargetPstPreview -cne [string]$Envelope.TargetPstPreview -or
           [string]$r.TargetFolderPath -cne '2020\Входящие' -or
           [long]$r.ArchiveDateLocalTicks -le 0 -or
           [long]$r.ArchiveDateUtcTicks -le 0 -or
           [int]$r.AttachmentCount -lt 0 -or
           [int]$r.AttachmentCount -gt 128 -or
           [string]$r.SubjectSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$r.FullOriginalWitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           -not (Test-OPA265ARCH2bWitnessSchema -Witness $r.OriginalWitness)){
            throw ('ARCH3v invalid original full-witness row '+($i+1))
        }
        $w=$r.OriginalWitness
        $actual=Get-OPA265ARCH3dOriginalWitnessHash -Witness $w
        if($actual -cne [string]$r.FullOriginalWitnessSha256 -or
           [string]$w.SubjectSha256 -cne [string]$r.SubjectSha256 -or
           [int]$w.AttachmentCount -ne [int]$r.AttachmentCount -or
           [long]$w.ReceivedUtcTicks -ne [long]$r.ArchiveDateUtcTicks){
            throw ('ARCH3v full original ARCH2b contents/attachment/date SHA mismatch at '+($i+1))
        }
        $totalAttachments+=[int]$r.AttachmentCount
        foreach($p in @([string]$r.Ordinal,[string]$r.SourceEntryId,
             [string]$r.OriginalContractSha256,[string]$r.OriginalOperationId,
             [string]$r.TargetFolderPath,[string]$r.ArchiveDateLocalTicks,
             [string]$r.ArchiveDateUtcTicks,[string]$r.AttachmentCount,
             [string]$r.SubjectSha256,[string]$r.FullOriginalWitnessSha256)){
             [void]$parts.Add($p)
        }
    }
    if([int]$Envelope.TotalAttachmentCount -ne $totalAttachments){
        throw 'ARCH3v total original attachment count differs from ten witnesses.'
    }
    return (Get-OPA265ARCH3bDigest -Parts @($parts.ToArray()))
}

function New-OPA265ARCH3vEnvelopeFromPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Preview,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$WitnessRows)
    if([string]$Preview.Schema -cne '2.6.5-ARCH3u.RealBatchTenPreview.1' -or
       [int]$Preview.BatchSize -ne 10 -or
       @($WitnessRows).Count -ne 10 -or
       [int]$Preview.SelectedYear -ne 2020 -or
       [int]$Preview.SelectedArchivePart -ne 3 -or
       [bool]$Preview.WriterPermit -or [bool]$Preview.ProductionReady){
        throw 'ARCH3v requires exact previously observed original ARCH3u 2020 Part3 ten preview.'
    }
    $n=0
    foreach($row in @($WitnessRows)){
        $v=$Preview.Rows[$n]
        if($null -eq $row -or
           [int]$row.Ordinal -ne ($n+1) -or
           [string]$row.SourceEntryId -cne [string]$v.SourceEntryId -or
           [string]$row.OriginalContractSha256 -cne [string]$v.OriginalContractSha256 -or
           [string]$row.TargetPstPreview -cne [string]$v.TargetPstPreview -or
           [string]$row.TargetFolderPath -cne [string]$v.TargetFolderPath -or
           [long]$row.ArchiveDateLocalTicks -ne ([datetime]$v.ArchiveDate).Ticks -or
           [int]$row.AttachmentCount -ne [int]$v.AttachmentCount -or
           [string]$row.SubjectSha256 -cne [string]$v.SubjectSha256){
            throw 'ARCH3v witness row differs from exact original ARCH3u preview.'
        }
        $n++
    }
    $total=0
    foreach($r in @($WitnessRows)){$total+=[int]$r.AttachmentCount}
    $envelope=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3v.OriginalTenFullWitnessEnvelope.1'
        RunId=[string]$Preview.RunId
        SourcePst=[string]$Preview.SourcePst
        PreviewSha256=[string]$Preview.PreviewSha256
        SourceStoreIdSha256=[string]$Preview.SourceStoreIdSha256
        OriginalIndexSha256=[string]$Preview.OriginalIndexSha256
        SourcePstLengthBytes=[long]$Preview.SourcePstLengthBytes
        ArchiveYear=[int]$Preview.SelectedYear
        ArchivePart=[int]$Preview.SelectedArchivePart
        TargetPstPreview=[string]$Preview.TargetPstPreview
        BatchSize=10
        TotalAttachmentCount=$total
        Rows=@($WitnessRows)
        RealMailMovePerformed=$false
        OriginalOperationJournalWritten=$false
        OriginalDuplicateIndexWritten=$false
        ArchivePstCreated=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
    $digest=Get-OPA265ARCH3vAuditDigest -Envelope $envelope
    return [pscustomobject]@{Envelope=$envelope;AuditSha256=$digest}
}

function Get-OPA265ARCH3vFullReadOnlyAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$ExpectedPreviewSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedSourceStoreIdSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedOriginalIndexSha256,
          [Parameter(Mandatory=$true)][long]$ExpectedSourcePstLengthBytes)
    [void](Assert-OPA265ARCH3vExactPins -RunId $RunId -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedSourceStoreIdSha256 $ExpectedSourceStoreIdSha256 -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256 -ExpectedSourcePstLengthBytes $ExpectedSourcePstLengthBytes)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting
    $p=Invoke-OPA265ARCH3uRealBatchTenPreflight -Mode Inventory -RunId $RunId -SourcePst $source
    if([string]$p.PreviewSha256 -cne $ExpectedPreviewSha256 -or
       [string]$p.SourceStoreIdSha256 -cne $ExpectedSourceStoreIdSha256 -or
       [string]$p.OriginalIndexSha256 -cne $ExpectedOriginalIndexSha256 -or
       [long]$p.SourcePstLengthBytes -ne $ExpectedSourcePstLengthBytes -or
       [int]$p.BatchSize -ne 10 -or @($p.Rows).Count -ne 10 -or
       [int]$p.SelectedYear -ne 2020 -or [int]$p.SelectedArchivePart -ne 3 -or
       [bool]$p.RealMailMovePerformed -or [bool]$p.WriterPermit -or
       [IO.File]::Exists([string]$p.TargetPstPreview)){
        throw 'ARCH3v immutable original operator ARCH3u pins/Part3 have drifted. STOP.'
    }
    $layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    $session=$null
    $records=New-Object 'System.Collections.Generic.List[object]'
    try {
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if([int]$session.OutlookProcessId -ne [int]$p.OutlookProcessId -or
           [long]$session.OutlookProcessStartUtcTicks -ne [long]$p.OutlookProcessStartUtcTicks -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne $ExpectedSourceStoreIdSha256){
            throw 'ARCH3v real Outlook process or original POP3 StoreID changed between read-only preflight and full witnesses.'
        }
        $i=0
        foreach($v in @($p.Rows)){
            $i++
            $mail=$null;$parent=$null
            try {
                $mail=$session.Namespace.GetItemFromID([string]$v.SourceEntryId,[string]$session.SourceStore.StoreID)
                if($null -eq $mail -or [int]$mail.Class -ne 43 -or
                   [string]$mail.EntryID -cne [string]$v.SourceEntryId){
                    throw ('ARCH3v exact source item missing at ordinal '+$i)
                }
                $parent=$mail.Parent
                $date=[datetime](Get-OPAArchiveItemDate -Item $mail)
                if($null -eq $parent -or
                   [string]$parent.EntryID -cne [string]$p.InboxEntryId -or
                   [string]$parent.StoreID -cne [string]$session.SourceStore.StoreID -or
                   $date.Ticks -ne ([datetime]$v.ArchiveDate).Ticks -or
                   [int]$mail.Attachments.Count -ne [int]$v.AttachmentCount -or
                   (Get-OPA265ARCH2bTextSha256 -Text ([string]$mail.Subject)) -cne [string]$v.SubjectSha256){
                    throw ('ARCH3v original POP3 parent/date/attachments/subject changed at '+$i)
                }
                # ORIGINAL full Body/HTML/recipients/user state and actual
                # SaveAsFile temporary attachment bytes with SHA256.
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                $h=Get-OPA265ARCH3dOriginalWitnessHash -Witness $w
                if([int]$w.AttachmentCount -ne [int]$v.AttachmentCount -or
                   [string]$w.SubjectSha256 -cne [string]$v.SubjectSha256 -or
                   [long]$w.ReceivedUtcTicks -ne [long]$date.ToUniversalTime().Ticks){
                    throw ('ARCH3v full original ARCH2b witness drift at ordinal '+$i)
                }
                [void]$records.Add([pscustomobject][ordered]@{
                    Ordinal=$i
                    SourceEntryId=[string]$v.SourceEntryId
                    OriginalOperationId=[string]$v.OriginalOperationId
                    OriginalContractSha256=[string]$v.OriginalContractSha256
                    TargetFolderPath=[string]$v.TargetFolderPath
                    TargetPstPreview=[string]$v.TargetPstPreview
                    ArchiveDateLocalTicks=[long]$date.Ticks
                    ArchiveDateUtcTicks=[long]$date.ToUniversalTime().Ticks
                    AttachmentCount=[int]$w.AttachmentCount
                    SubjectSha256=[string]$w.SubjectSha256
                    FullOriginalWitnessSha256=$h
                    OriginalWitness=$w
                })
            }finally{
                Release-OPA265ARCH2c4Com -Object $parent
                Release-OPA265ARCH2c4Com -Object $mail
            }
        }
        if((Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne $ExpectedSourceStoreIdSha256 -or
           [int]$session.OutlookProcessId -ne [int]$p.OutlookProcessId -or
           [int]$session.Inbox.Items.Count -lt 10 -or
           ([IO.FileInfo]::new($source)).Length -ne $ExpectedSourcePstLengthBytes -or
           [IO.File]::Exists([string]$p.TargetPstPreview)){
            throw 'ARCH3v original POP3 source or target changed during ten full witnesses.'
        }
        $finalIndex=Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst $source
        if([string]$finalIndex.OriginalIndexSha256 -cne $ExpectedOriginalIndexSha256){
            throw 'ARCH3v original shared index changed while building full semantic witnesses.'
        }
    }finally {Close-OPA265ARCH2dSession -Session $session}
    $bundle=New-OPA265ARCH3vEnvelopeFromPreview -Preview $p -WitnessRows @($records.ToArray())
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3v.OriginalTenFullWitnessAudit.1'
        Status='ExactTenOriginalFullSemanticsComputedNoPstOrJournalWrites'
        RunId=$RunId;SourcePst=$source
        PreviewSha256=$ExpectedPreviewSha256
        SourceStoreIdSha256=$ExpectedSourceStoreIdSha256
        OriginalIndexSha256=$ExpectedOriginalIndexSha256
        SourcePstLengthBytes=$ExpectedSourcePstLengthBytes
        TargetPstPreview=[string]$p.TargetPstPreview
        AuditSha256=[string]$bundle.AuditSha256
        BatchSize=10
        TotalAttachmentCount=[int]$bundle.Envelope.TotalAttachmentCount
        Rows=@($records.ToArray() | ForEach-Object{
            [pscustomobject][ordered]@{
                Ordinal=[int]$_.Ordinal;SourceEntryId=[string]$_.SourceEntryId
                FullOriginalWitnessSha256=[string]$_.FullOriginalWitnessSha256
                AttachmentCount=[int]$_.AttachmentCount
                OriginalContractSha256=[string]$_.OriginalContractSha256
            }
        })
        # Internal-only full hash witness bundle returned for the Seal call:
        # never persist anything until external hash pin is compared.
        _Envelope=$bundle.Envelope
        FullOriginalSemanticWitnessesCaptured=$true
        SealedEvidenceWritten=$false
        OriginalOperationJournalWritten=$false
        OriginalDuplicateIndexWritten=$false
        RealPstWritten=$false;RealMailMovePerformed=$false
        AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Test-OPA265ARCH3vFullTenReadback {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SealSha256)
    if($SealSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.Directory]::Exists([string]$Layout.Root) -or
       (([IO.File]::GetAttributes([string]$Layout.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3v missing or unsafe protected evidence folder.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
    $f=[string]$Layout.WitnessPath
    if(-not [IO.File]::Exists($f) -or
       (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       @([IO.Directory]::GetFileSystemEntries([string]$Layout.Root)).Count -ne 1){
        throw 'ARCH3v expected one exact immutable full witness file; unexpected/unsafe content.'
    }
    $doc=Read-OPA265ARCH3cPinnedJson -Path $f -ExpectedSha256 $SealSha256
    if([string]$doc.RunId -cne [string]$Layout.RunId -or
       -not [bool]$doc.FullOriginalSemanticWitnessesCaptured -or
       -not [bool]$doc.SealedEvidenceWritten -or
       [bool]$doc.RealMailMovePerformed -or
       [bool]$doc.WriterPermit -or [bool]$doc.ProductionReady){
        throw 'ARCH3v sealed evidence flags/provenance invalid.'
    }
    $auditSha=Get-OPA265ARCH3vAuditDigest -Envelope $doc
    if($auditSha -cne [string]$doc.AuditSha256){throw 'ARCH3v sealed Audit SHA drift: content or attachment fingerprint mismatch.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3v.IndependentTenSealReadback.1'
        Status='TenOriginalFullSemanticsSealedIndependentlyReadBackNoMove'
        RunId=[string]$doc.RunId
        PreviewSha256=[string]$doc.PreviewSha256
        OriginalIndexSha256=[string]$doc.OriginalIndexSha256
        AuditSha256=$auditSha
        SealSha256=$SealSha256
        SealPath=$f
        BatchSize=10
        FullOriginalWitnessesVerified=10
        TotalAttachmentCount=[int]$doc.TotalAttachmentCount
        FullOriginalSemanticWitnessesCaptured=$true
        SealedEvidenceWritten=$true
        IndependentReadbackPassed=$true
        OriginalOperationJournalWritten=$false
        OriginalDuplicateIndexWritten=$false
        RealPstWritten=$false;RealMailMovePerformed=$false
        AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3vRealTenFullWitness {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Seal','Review')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [string]$SourcePst='',
        [string]$ExpectedPreviewSha256='',
        [string]$ExpectedSourceStoreIdSha256='',
        [string]$ExpectedOriginalIndexSha256='',
        [long]$ExpectedSourcePstLengthBytes=0,
        [string]$ExpectedAuditSha256='',
        [string]$SealSha256='',
        [switch]$ConfirmEvidenceWrite
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3v requires Windows PowerShell 5.1.'
    }
    $layout=Get-OPA265ARCH3vEvidenceLayout -RunId $RunId
    if($Mode -ceq 'Review'){
        if($ConfirmEvidenceWrite -or $SourcePst -or $ExpectedAuditSha256 -or
           $ExpectedPreviewSha256 -or $ExpectedSourceStoreIdSha256 -or $ExpectedOriginalIndexSha256 -or
           $ExpectedSourcePstLengthBytes -gt 0){
            throw 'ARCH3v Review only accepts exact RunId and sealed evidence SHA256.'
        }
        return (Test-OPA265ARCH3vFullTenReadback -Layout $layout -SealSha256 $SealSha256)
    }
    if(-not $SourcePst){throw 'ARCH3v Plan/Audit/Seal require explicit test SourcePst.'}
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -cne 'Plan')
    if($ConfirmEvidenceWrite -and $Mode -cne 'Seal'){throw 'ARCH3v evidence write confirmation only valid in Seal.'}
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3v.Plan.1'
            Status='ExactRealTenFullOriginalWitnessPlanNoOutlookNoWrites'
            RunId=$RunId;SourcePst=$source;BatchSize=10
            EvidenceRoot=[string]$layout.Root
            OriginalARCH3uPreviewMustBeReverified=$true
            OriginalARCH2bAttachmentPayloadShaRequired=$true
            OriginalARCH3iPrivateAclEvidenceWriterReused=$true
            OutlookContacted=$false;EvidenceWritten=$false
            RealMailMovePerformed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    [void](Assert-OPA265ARCH3vExactPins -RunId $RunId -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedSourceStoreIdSha256 $ExpectedSourceStoreIdSha256 -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256 -ExpectedSourcePstLengthBytes $ExpectedSourcePstLengthBytes)
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3v real full witness requires Windows PowerShell 5.1 -STA.'
    }
    if($Mode -ceq 'Audit'){
        if($ExpectedAuditSha256 -or $SealSha256){
            throw 'ARCH3v Audit takes only original ARCH3u external preflight SHA pins.'
        }
        $audit=Get-OPA265ARCH3vFullReadOnlyAudit -RunId $RunId -SourcePst $source -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedSourceStoreIdSha256 $ExpectedSourceStoreIdSha256 -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256 -ExpectedSourcePstLengthBytes $ExpectedSourcePstLengthBytes
        $audit.PSObject.Properties.Remove('_Envelope')
        return $audit
    }
    if($ExpectedAuditSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not $ConfirmEvidenceWrite -or $SealSha256){
        throw 'ARCH3v Seal requires explicit -ConfirmEvidenceWrite and independently observed AuditSha256.'
    }
    if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
        throw 'ARCH3v evidence already exists. No replay, no overwrite and no baseline reset.'
    }
    if(-not $PSCmdlet.ShouldProcess([string]$layout.WitnessPath,'Seal ten ORIGINAL full semantic witness SHA256 records ONLY in private LOCALAPPDATA')){
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3v.WhatIf.1';Status='EvidenceSealWhatIfNoWrites'
            RunId=$RunId;EvidenceWritten=$false
            RealMailMovePerformed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    # External AuditSHA is compared BEFORE any persisted evidence write.
    $audit=Get-OPA265ARCH3vFullReadOnlyAudit -RunId $RunId -SourcePst $source -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedSourceStoreIdSha256 $ExpectedSourceStoreIdSha256 -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256 -ExpectedSourcePstLengthBytes $ExpectedSourcePstLengthBytes
    if([string]$audit.AuditSha256 -cne $ExpectedAuditSha256){
        throw 'ARCH3v full original semantic audit changed from operator pin. STOP before evidence write.'
    }
    $record=$audit._Envelope
    $record | Add-Member -NotePropertyName AuditSha256 -NotePropertyValue $ExpectedAuditSha256
    $record | Add-Member -NotePropertyName FullOriginalSemanticWitnessesCaptured -NotePropertyValue $true
    $record | Add-Member -NotePropertyName SealedEvidenceWritten -NotePropertyValue $true
    New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
    $seal=Write-OPA265ARCH3cJsonOnce -Path ([string]$layout.WitnessPath) -Record $record
    return (Test-OPA265ARCH3vFullTenReadback -Layout $layout -SealSha256 $seal)
}
