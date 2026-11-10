#requires -Version 5.1
# BW4k7v2a5 pure classifier. The old failed BW4k7v2a4 SuiteId must never be retried.
function Test-OPA265BW4k7v2a5CountEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Source,
        [Parameter(Mandatory=$true)][object]$Target
    )
    $issues=New-Object 'System.Collections.Generic.List[string]'
    foreach($one in @($Source,$Target)){
        foreach($name in @('FullItemsCount','RestrictCount','ManualExactSubjectCount',
                'MatchingCandidates','ReadComplete','RestrictionReadComplete')){
            if($one.PSObject.Properties.Name -cnotcontains $name -or
                $null -eq $one.PSObject.Properties[$name].Value){
                throw ('BW4k7v2a5 missing observed field '+$name)
            }
        }
        foreach($n in @('FullItemsCount','RestrictCount','ManualExactSubjectCount')){
            $v=[int]$one.$n
            if($v -lt 0 -or $v -gt 32){throw ('BW4k7v2a5 invalid count '+$n)}
        }
        if(@($one.MatchingCandidates).Count -ne [int]$one.ManualExactSubjectCount){
            throw 'BW4k7v2a5 invalid count vs actual candidates.'
        }
        if([int]$one.ManualExactSubjectCount -gt [int]$one.FullItemsCount){
            throw 'BW4k7v2a5 more subject matches than Items.Count.'
        }
    }
    $complete=([bool]$Source.ReadComplete -and [bool]$Target.ReadComplete -and
        [bool]$Source.RestrictionReadComplete -and [bool]$Target.RestrictionReadComplete)
    $sourceMismatch=([int]$Source.RestrictCount -ne [int]$Source.ManualExactSubjectCount)
    $targetMismatch=([int]$Target.RestrictCount -ne [int]$Target.ManualExactSubjectCount)
    if(-not $complete){$issues.Add('ProviderOrBoundedReadIncomplete')}
    if($sourceMismatch){$issues.Add('SourceRestrictCountDisagreesWithManualSubjects')}
    if($targetMismatch){$issues.Add('TargetRestrictCountDisagreesWithManualSubjects')}
    if([int]$Source.ManualExactSubjectCount -ne 1){$issues.Add('ManualSourceNotExactlyOne')}
    if([int]$Target.ManualExactSubjectCount -ne 0){$issues.Add('ManualTargetNotZero')}
    $status='ReadOnlyIncompleteOrAmbiguousCountsNeedsManualReview'
    if($complete -and $sourceMismatch){$status='SourceRestrictManualCountDiscrepancyObserved'}
    elseif($complete -and $targetMismatch){$status='TargetRestrictManualCountDiscrepancyObserved'}
    elseif($complete -and [int]$Source.ManualExactSubjectCount -eq 1 -and
           [int]$Target.ManualExactSubjectCount -eq 0){
        $status='NowSourceOneTargetZeroButOriginalFailureCauseUnproven'
    }elseif($complete){$status='CurrentSourceTargetCardinalityNotPreMoveExpected'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a5.CountEvidence.1'
        Status=$status
        ReasonCodes=@($issues.ToArray())
        ExactHistoricalFailedPredicateProven=$false
        SourceRestrictionMatchesManual=(-not $sourceMismatch)
        TargetRestrictionMatchesManual=(-not $targetMismatch)
        ObservedSourceManualSubjectCount=[int]$Source.ManualExactSubjectCount
        ObservedTargetManualSubjectCount=[int]$Target.ManualExactSubjectCount
        CompleteRead=$complete
        OriginalCreatePilotMayBeRetried=$false
        OriginalMovePilotMayBeInvoked=$false
        OutlookWriterUsed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}