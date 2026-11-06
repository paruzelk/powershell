#requires -Version 5.1
# BW4k7v2a3: pure synthetic observation classification. Never touches Outlook.
function Test-OPA265BW4k7v2a3DraftsEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Rows
    )
    if($null -eq $Rows -or $Rows.Count -eq 0){
        throw 'BW4k7v2a3 no store observations; fail closed.'
    }
    if($Rows.Count -gt 32){
        throw 'BW4k7v2a3 >32 stores; fail closed.'
    }
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $count=0
    $incomplete=$false
    $readCount=0
    $absentCount=0
    $allMatches=New-Object 'System.Collections.Generic.List[object]'
    foreach($row in $Rows){
        if($null -eq $row){throw 'BW4k7v2a3 null store observation.'}
        foreach($name in @('StoreIdSha256','Status','Matches')){
            if($row.PSObject.Properties.Name -cnotcontains $name -or
               $null -eq $row.PSObject.Properties[$name].Value){
                throw ('BW4k7v2a3 missing '+$name)
            }
        }
        $id=[string]$row.StoreIdSha256
        if($id -cnotmatch '^[a-f0-9]{64}$' -or -not $ids.Add($id)){
            throw 'BW4k7v2a3 repeated or invalid hashed StoreID.'
        }
        $state=[string]$row.Status
        if($state -cnotin @('Read','NoDraftsFolder','ProviderError','MatchLimitExceeded')){
            throw 'BW4k7v2a3 invalid store state.'
        }
        $matches=@($row.Matches)
        if($matches.Count -gt 8){throw 'BW4k7v2a3 exceeded matched-mail bound.'}
        if($state -cne 'Read' -and $matches.Count -gt 0){
            throw 'BW4k7v2a3 non-read state with matches.'
        }
        if($state -ceq 'Read'){$readCount++}
        if($state -ceq 'NoDraftsFolder'){$absentCount++}
        if($state -cin @('ProviderError','MatchLimitExceeded')){$incomplete=$true}
        foreach($candidate in $matches){
            if($null -eq $candidate -or
               $candidate.PSObject.Properties.Name -cnotcontains 'SubjectMatches' -or
               $candidate.PSObject.Properties.Name -cnotcontains 'StoreIdSha256' -or
               $candidate.PSObject.Properties.Name -cnotcontains 'ClassIsMail' -or
               $null -eq $candidate.SubjectMatches -or
               $null -eq $candidate.ClassIsMail -or
               $null -eq $candidate.StoreIdSha256 -or
               -not [bool]$candidate.SubjectMatches -or
               [string]$candidate.StoreIdSha256 -cne $id){
                throw 'BW4k7v2a3 malformed match or wrong StoreID.'
            }
            $allMatches.Add($candidate)
            $count++
            if($count -gt 16){throw 'BW4k7v2a3 aggregate matched-mail bound exceeded.'}
        }
    }
    $status='NoPilotFoundInCheckedDraftsFolders'
    if($count -gt 1){$status='MultipleMatchingPilotsManualReview'}
    elseif($count -eq 1 -and $incomplete){$status='SinglePilotFoundButOtherDraftsChecksIncomplete'}
    elseif($count -eq 1){$status='SinglePilotLocatedInDraftsReadOnly'}
    elseif($incomplete){$status='IncompleteDraftsSearchNoConclusion'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a3.DraftsEvidence.1'
        Status=$status
        InspectedStoreCount=$Rows.Count
        ReadDraftsFolderCount=$readCount
        AbsentDraftsFolderCount=$absentCount
        ExactSubjectMatchCount=$count
        AnyDraftsInspectionIncomplete=$incomplete
        ExactMatchOutsideDraftsProvenAbsent=$false
        ActualPreviousSaveDestinationHistoricallyProven=$false
        MatchCandidates=@($allMatches.ToArray())
        OriginalSuiteIdRetryPermitted=$false
        OutlookComWriterUsed=$false
        ProductionReady=$false
        WriterPermit=$false
    }
}