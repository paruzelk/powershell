#requires -Version 5.1
# ARCH3x1b: ten specifically sealed MailItems, NOT a snapshot of changing PST.
# Never use a raw PST byte length, full-file SHA, folder item count or a
# reselected first-ten chronological Inbox preview for the Move permit.
# Existing one-item Part2 is still independently checked by ORIGINAL verifier.
. (Join-Path $PSScriptRoot 'ARCH3w1SemanticPart2Intents.ps1')

function Get-OPA265ARCH3x1bPartsProof {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$Manifest.SourcePst) -RequireExisting
    $target=[string]$Manifest.TargetPstPreview
    if([IO.File]::Exists($target) -or [IO.Directory]::Exists($target)){
        throw 'ARCH3x1b new Year2020 Part3 must be absent.'
    }
    Clear-OPAArchivePartCache -SourcePst $source
    $known=@(Get-OPAArchivePstPartsOnDiskAll -SourcePst $source | Where-Object {[int]$_.Year -eq 2020})
    if($known.Count -ne 2){throw 'ARCH3x1b exactly two historical 2020 archive parts expected.'}
    $parts=@($Manifest.ExistingArchiveParts)
    if($parts.Count -ne 2){throw 'ARCH3x1b historical archive part manifest invalid.'}
    for($i=0;$i -lt 2;$i++){
        $path=[string]$parts[$i].Path
        if([int]$parts[$i].Part -ne ($i+1) -or
           @($known | Where-Object {[int]$_.Part -eq ($i+1) -and [string]$_.Path -ceq $path}).Count -ne 1 -or
           -not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           [string]$path -cne (Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part ($i+1))){
            throw 'ARCH3x1b original archive part path missing, ambiguous or redirected.'
        }
    }
    $historical=Get-OPA265ARCH3w1HistoricalEvidence -Part2 ([string]$parts[1].Path)
    if([string]$historical.SemanticSha256 -cne [string]$parts[1].Sha256){
        throw 'ARCH3x1b original historical Part2 semantic SHA drift.'
    }
    $live=Test-OPA265ARCH3w1LiveOriginalPart2 -SourcePst $source -Part2 ([string]$parts[1].Path) -Evidence $historical
    if(-not [bool]$live.OriginalArchiveVerifierUsed -or
       [int]$live.OriginalPart2TotalItemCount -ne 1 -or
       [string]$live.SemanticSha256 -cne [string]$parts[1].Sha256){
        throw 'ARCH3x1b ORIGINAL Part2 single-item full semantic ArchiveVerifier failed.'
    }
    return [pscustomobject][ordered]@{
        OriginalPart1Path=[string]$parts[0].Path
        OriginalPart2Path=[string]$parts[1].Path
        OriginalPart2SemanticSha256=[string]$live.SemanticSha256
        OriginalArchiveVerifierPart2Passed=$true
        Part3Absent=$true
    }
}

function Get-OPA265ARCH3x1bPinnedTenLiveAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Seal)
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3x1b original ten live semantic audit requires PowerShell 5.1 -STA.'
    }
    if([string]$Seal.RunId -cne [string]$Manifest.RunId -or
       [string]$Seal.PreviewSha256 -cne [string]$Manifest.PreviewSha256 -or
       [string]$Seal.AuditSha256 -cne [string]$Manifest.AuditSha256 -or
       [string]$Seal.SourceStoreIdSha256 -cne [string]$Manifest.SourceStoreIdSha256 -or
       @($Manifest.Rows).Count -ne 10 -or @($Seal.Rows).Count -ne 10 -or
       [int]$Manifest.TotalAttachmentCount -ne 12){
        throw 'ARCH3x1b original ten protected source manifest and full witness seal mismatch.'
    }
    $session=$null;$rows=New-Object 'System.Collections.Generic.List[object]'
    $source=[string]$Manifest.SourcePst
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId ([string]$Manifest.RunId) -LocalAppData $env:LOCALAPPDATA) -SourcePst $source
        if(-not [bool]$session.Scope.Approved -or
           [string]$session.Namespace.CurrentProfileName -cne 'Outlook' -or
           [string]$session.Inbox.FolderPath -cne '\\info@stios.ru\Входящие' -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$Manifest.SourceStoreIdSha256){
            throw 'ARCH3x1b approved original POP3 Store/Inbox scope changed.'
        }
        for($i=0;$i -lt 10;$i++){
            $r=$Manifest.Rows[$i];$v=$Seal.Rows[$i];$mail=$null;$parent=$null
            try{
                if([int]$r.Ordinal -ne ($i+1) -or
                   [int]$v.Ordinal -ne ($i+1) -or
                   [string]$r.SourceEntryId -cne [string]$v.SourceEntryId -or
                   [string]$r.FullOriginalWitnessSha256 -cne [string]$v.FullOriginalWitnessSha256 -or
                   [string]$r.OriginalContractSha256 -cne [string]$v.OriginalContractSha256 -or
                   [string]$r.OriginalOperationId -cne [string]$v.OriginalOperationId){
                    throw ('ARCH3x1b original sealed ten identity/contract drift at '+($i+1))
                }
                $mail=$session.Namespace.GetItemFromID([string]$r.SourceEntryId,[string]$session.SourceStore.StoreID)
                if($null -eq $mail -or [int]$mail.Class -ne 43 -or
                   [string]$mail.EntryID -cne [string]$r.SourceEntryId){
                    throw ('ARCH3x1b pinned source mail missing, moved or deleted at ordinal '+($i+1))
                }
                $parent=$mail.Parent
                $date=Get-OPAArchiveItemDate -Item $mail
                if($null -eq $parent -or
                   [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
                   [string]$parent.StoreID -cne [string]$session.SourceStore.StoreID -or
                   $null -eq $date -or [long]([datetime]$date).Ticks -ne [long]$v.ArchiveDateLocalTicks){
                    throw ('ARCH3x1b exact source parent/date changed at '+($i+1))
                }
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $w -ExpectedOriginalWitnessSha256 ([string]$r.FullOriginalWitnessSha256))
                $compare=Compare-OPA265ARCH2bMailSemanticWitness -Source $v.OriginalWitness -Destination $w
                if(-not [bool]$compare.CriticalContentMatches -or
                   @($compare.IssueCodes).Count -gt 0 -or
                   [int]$w.AttachmentCount -ne [int]$r.AttachmentCount){
                    throw ('ARCH3x1b original full Body/HTML/attachment witness changed at '+($i+1))
                }
                [void]$rows.Add([pscustomobject][ordered]@{
                    Ordinal=$i+1
                    SourceEntryId=[string]$r.SourceEntryId
                    OriginalOperationId=[string]$r.OriginalOperationId
                    OriginalContractSha256=[string]$r.OriginalContractSha256
                    FullOriginalWitnessSha256=[string]$r.FullOriginalWitnessSha256
                    AttachmentCount=[int]$w.AttachmentCount
                })
            }finally{
                Release-OPA265ARCH2c4Com -Object $parent
                Release-OPA265ARCH2c4Com -Object $mail
            }
        }
        if((Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$Manifest.SourceStoreIdSha256){
            throw 'ARCH3x1b POP3 source StoreID changed during ten full semantic witnesses.'
        }
    }finally {Close-OPA265ARCH2dSession -Session $session}
    $totalAttachments=($rows.ToArray() | Measure-Object -Property AttachmentCount -Sum).Sum
    if([int]$totalAttachments -ne 12){
        throw 'ARCH3x1b ten original attachments no longer total twelve.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x1b.PinnedTenLiveFullWitnessAudit.1'
        Status='ExactProtectedTenSourceEntryIdsAndFullSemanticWitnessesMatchNoPstSizeFence'
        RunId=[string]$Manifest.RunId
        AuditSha256=[string]$Manifest.AuditSha256
        FullOriginalWitnessCount=10
        TotalAttachmentCount=12
        Rows=@($rows.ToArray())
        ReSelectedInboxCandidates=$false
        PhysicalPstSizeCompared=$false
        OriginalArchiveDateAndParentMatched=$true
        RealMailMovePerformed=$false
        ProductionReady=$false
    }
}
