#requires -Version 5.1
# BW4k2: independent READ-ONLY validation for BW4k1 real disposable Move.
# NO writer, no journal mutation, no claim update, no size-drift acceptance.
function Assert-OPA265BW4k2Claim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Claim,
          [Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$PlanSha256,
          [Parameter(Mandatory=$true)][string]$FiveSealSha256,
          [Parameter(Mandatory=$true)][string]$SourceEvidenceSha256,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$DestinationPst,
          [Parameter(Mandatory=$true)][string]$DestinationFolderEntryId,
          [Parameter(Mandatory=$true)][string]$SourceEntryId)
    $fields=@('Schema','SuiteId','TestId','CaseName','PlanSha256',
        'EvidenceSetSha256','SourceEvidenceSha256','SourcePst','SourceEntryId',
        'SourceFolderEntryId','InternetMessageId','DestinationPst',
        'DestinationFolderEntryId','ClaimUtc','RealOutlookOneShot',
        'AutomaticRetryAllowed','ProductionReady')
    if(@($Claim.PSObject.Properties.Name).Count -ne $fields.Count){
        throw 'BW4k2 claim schema property count differs.'
    }
    foreach($f in $fields){
        if($Claim.PSObject.Properties.Name -cnotcontains $f){
            throw ('BW4k2 missing claim property '+$f)
        }
    }
    $expected=@{
        Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName=[string]$Original.CaseName
        PlanSha256=$PlanSha256;EvidenceSetSha256=$FiveSealSha256
        SourceEvidenceSha256=$SourceEvidenceSha256
        SourceEntryId=$SourceEntryId
        SourceFolderEntryId=[string]$Original.FolderEntryId
        InternetMessageId=[string]$Original.InternetMessageId
        DestinationFolderEntryId=$DestinationFolderEntryId
    }
    foreach($key in $expected.Keys){
        if([string]$Claim.$key -cne [string]$expected[$key]){
            throw ('BW4k2 pinned claim property differs: '+$key)
        }
    }
    foreach($key in @('SourcePst','DestinationPst')){
        $expectedPath=if($key -ceq 'SourcePst'){$SourcePst}else{$DestinationPst}
        if(-not [IO.Path]::IsPathRooted($expectedPath) -or
           -not [string]::Equals([IO.Path]::GetFullPath([string]$Claim.$key),
                [IO.Path]::GetFullPath($expectedPath),
                [StringComparison]::OrdinalIgnoreCase)){
            throw ('BW4k2 pinned claim PST path mismatch: '+$key)
        }
    }
    if($Claim.RealOutlookOneShot -isnot [bool] -or -not $Claim.RealOutlookOneShot -or
       $Claim.AutomaticRetryAllowed -isnot [bool] -or $Claim.AutomaticRetryAllowed -or
       $Claim.ProductionReady -isnot [bool] -or $Claim.ProductionReady){
        throw 'BW4k2 unsafe real move claim flags.'
    }
    $date=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Claim.ClaimUtc,[ref]$date)){
        throw 'BW4k2 invalid immutable ClaimUtc.'
    }
    return $true
}
function Assert-OPA265BW4k2IndependentAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Audit,
          [Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$PlanSha256,
          [Parameter(Mandatory=$true)][string]$SourceEvidenceSha256)
    $expectedStatus='OnlyMAPIMessageSizeChangedNeedsManualReview'
    if([string]$Audit.Schema -cne '2.6.5-BW4j.IndependentSourceDestinationReadOnly.1' -or
       [string]$Audit.Status -cne $expectedStatus -or
       [string]$Audit.SuiteId -cne $SuiteId -or
       [string]$Audit.TestId -cne $TestId -or
       [string]$Audit.CaseName -cne [string]$Original.CaseName -or
       [string]$Audit.OriginalSuitePlanSha256 -cne $PlanSha256 -or
       [string]$Audit.OriginalSourceEvidenceSha256 -cne $SourceEvidenceSha256){
        throw 'BW4k2 independent audit identity, source seal or drift status differs.'
    }
    if([int]$Audit.SourceMessageIdMatches -ne 0 -or
       [int]$Audit.DestinationMessageIdMatches -ne 1 -or
       [long]$Audit.SourceSize -ne [long]$Original.Size -or
       [long]$Audit.DeltaSize -ne ([long]$Audit.DestinationSize - [long]$Audit.SourceSize)){
        throw 'BW4k2 source-zero/target-one/size arithmetic differs.'
    }
    foreach($f in @('SubjectMatches','SenderMatches','BodyMatches',
        'HtmlBodyMatches','ReceivedUtcTicksMatches','AttachmentsMatch',
        'HistoricalSevenHashesUnchanged')){
        if($Audit.$f -isnot [bool] -or -not $Audit.$f){
            throw ('BW4k2 mandatory field mismatch: '+$f)
        }
    }
    foreach($f in @('FullMAPIByteEqualityProven','PhysicalPstDurabilityProven',
       'OutlookMoveExecutedByThisAudit','CanRetryMove',
       'CanWriteHistoricalJournal','ProductionReady')){
        if($Audit.$f -isnot [bool] -or $Audit.$f){
            throw ('BW4k2 audit unsafe capability or overclaimed proof: '+$f)
        }
    }
    # Drift stays explicit. No global +38 byte allowance: this outcome is
    # reportable ONLY with every source witness and claim identity pinned.
    if([long]$Audit.DeltaSize -eq 0){
        throw 'BW4k2 expected audited size drift, not an exact-size status.'
    }
    return $true
}
function Assert-OPA265BW4k2StableAudits {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    $fields=@('Schema','Status','SuiteId','TestId','CaseName',
      'SourceMessageIdMatches','DestinationMessageIdMatches',
      'SubjectMatches','SenderMatches','BodyMatches','HtmlBodyMatches',
      'ReceivedUtcTicksMatches','AttachmentsMatch','SourceSize',
      'DestinationSize','DeltaSize','OriginalSourceEvidenceSha256',
      'OriginalSuitePlanSha256','HistoricalSevenHashesUnchanged',
      'FullMAPIByteEqualityProven','PhysicalPstDurabilityProven',
      'OutlookMoveExecutedByThisAudit','CanRetryMove',
      'CanWriteHistoricalJournal','ProductionReady')
    foreach($f in $fields){
        if([string]$First.$f -cne [string]$Second.$f){
            throw ('BW4k2 two independent audits disagree: '+$f)
        }
    }
    return $true
}
