#requires -Version 5.1
# BW4k7s pure POP3 non-MailItem classification and Office 16.0 PST registry policy.
# No Outlook calls, no registry writes, no PST, Claim or journal mutation.
function Get-OPA265BW4k7sObjectClassName {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$ClassCode)
    $known=@{
        26='olAppointment';40='olContact';41='olDocument';42='olJournal'
        43='olMail';44='olNote';45='olPost';46='olReport';47='olRemote'
        48='olTask';49='olTaskRequest';50='olTaskRequestUpdate'
        51='olTaskRequestAccept';52='olTaskRequestDecline'
        53='olMeetingRequest';54='olMeetingCancellation'
        55='olMeetingResponseNegative';56='olMeetingResponsePositive'
        57='olMeetingResponseTentative';104='olSharing'
        181='olMeetingForwardNotification'
    }
    if($known.ContainsKey($ClassCode)){return [string]$known[$ClassCode]}
    return 'UnknownOlObjectClass'
}
function New-OPA265BW4k7sNonMailWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][int]$ClassCode,
        [Parameter(Mandatory=$true)][string]$EntryId,
        [Parameter(Mandatory=$true)][string]$FolderEntryId,
        [string]$MessageClass='',
        [ValidateSet('Read','NotAvailable')][string]$MessageClassObservation='NotAvailable'
    )
    if($ClassCode -eq 43){throw 'BW4k7s MailItem cannot be classified as non-mail witness.'}
    if([string]::IsNullOrWhiteSpace($EntryId) -or
       [string]::IsNullOrWhiteSpace($FolderEntryId)){
        throw 'BW4k7s cannot classify an item without immutable Outlook EntryID and folder identity.'
    }
    if($MessageClassObservation -ceq 'Read' -and
       [string]::IsNullOrWhiteSpace($MessageClass)){
        throw 'BW4k7s claimed MessageClass read without a value.'
    }
    if($MessageClass.Length -gt 512){throw 'BW4k7s MessageClass metadata exceeds bound.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.NonMailWitness.1'
        Class=[int]$ClassCode
        OlObjectClassName=(Get-OPA265BW4k7sObjectClassName -ClassCode $ClassCode)
        MessageClass=[string]$MessageClass
        MessageClassObservation=$MessageClassObservation
        EntryId=$EntryId
        FolderEntryId=$FolderEntryId
        IsMailItem=$false
        MessageBodyOrAttachmentPayloadRead=$false
        RequiresManualPreservationDecision=$true
        MayContainUserData=$true
        CanAutomaticallyDeleteSkipOrMove=$false
    }
}
function Get-OPA265BW4k7sPstRegistryProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Policy','User')][string]$Kind
    )
    $sub=if($Kind -eq 'Policy'){
        'Software\Policies\Microsoft\Office\16.0\Outlook\PST'
    }else{'Software\Microsoft\Office\16.0\Outlook\PST'}
    $path='Registry::HKEY_CURRENT_USER\'+$sub
    $values=[ordered]@{}
    $names=@('MaxLargeFileSize','WarnLargeFileSize','MaxFileSize','WarnFileSize')
    $exists=Test-Path -LiteralPath $path -ErrorAction Stop
    $key=$null
    try{
        if($exists){$key=Get-Item -LiteralPath $path -ErrorAction Stop}
        foreach($n in $names){
            $present=($null -ne $key -and ($key.GetValueNames() -ccontains $n))
            $kindName='NotConfigured';$raw=$null
            if($present){
                $kindName=[string]$key.GetValueKind($n)
                if($kindName -ceq 'DWord'){
                    $raw=[long]([uint32]$key.GetValue($n))
                }
            }
            $values[$n]=[pscustomobject][ordered]@{
                Name=$n
                Present=[bool]$present
                RegistryValueKind=$kindName
                DecimalDwordValue=$raw
                Unit=if($n -like '*Large*'){'MiB (1048576 bytes)'}else{'bytes (ANSI only)'}
            }
        }
    }finally{
        if($null -ne $key){$key.Close()}
    }
    return [pscustomobject][ordered]@{
        Kind=$Kind
        RegistryPath=$path
        RegistryKeyExists=[bool]$exists
        Values=[pscustomobject]$values
        ReadOnly=$true
        RegistryValuesWritten=$false
    }
}
function Get-OPA265BW4k7sPstLimitDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$PolicyProbe,
        [Parameter(Mandatory=$true)][psobject]$UserProbe,
        [ValidateRange(104857600,1099511627776)][long]$PlannedMaxArchivePstBytes=45000000000,
        [ValidateRange(0,1099511627775)][long]$PlannedSafetyMarginBytes=3000000000
    )
    if($PolicyProbe.Kind -cne 'Policy' -or $UserProbe.Kind -cne 'User'){
        throw 'BW4k7s requires one exact Policy and one exact User registry observation.'
    }
    if($PlannedSafetyMarginBytes -ge $PlannedMaxArchivePstBytes){
        throw 'BW4k7s planned safety margin cannot exceed or equal planned maximum.'
    }
    $all=@($PolicyProbe,$UserProbe)
    $invalid=New-Object 'System.Collections.Generic.List[string]'
    $anyPolicy=$false;$anyUser=$false
    foreach($p in $all){
        foreach($n in @('MaxLargeFileSize','WarnLargeFileSize','MaxFileSize','WarnFileSize')){
            $v=$p.Values.$n
            if($null -eq $v){throw ('BW4k7s registry probe missing '+$n)}
            if($v.Present){
                if($p.Kind -ceq 'Policy'){$anyPolicy=$true}else{$anyUser=$true}
                if($v.RegistryValueKind -cne 'DWord' -or $null -eq $v.DecimalDwordValue){
                    $invalid.Add($p.Kind+':'+$n+':NotDWORD')
                }elseif([long]$v.DecimalDwordValue -lt 0 -or
                       [long]$v.DecimalDwordValue -gt 4294967295L){
                    $invalid.Add($p.Kind+':'+$n+':NotUint32')
                }
            }
        }
    }
    $source=if($anyPolicy){'Policy'}elseif($anyUser){'User'}else{'MicrosoftDocumentedDefaultAssumed'}
    $chosen=if($source -eq 'Policy'){$PolicyProbe}
            elseif($source -eq 'User'){$UserProbe}else{$null}
    $maxMb=51200L;$warnMb=48640L
    $pairComplete=$false
    if($null -ne $chosen){
        $x=$chosen.Values.MaxLargeFileSize
        $y=$chosen.Values.WarnLargeFileSize
        $pairComplete=([bool]$x.Present -and [bool]$y.Present)
        if($pairComplete -and $x.RegistryValueKind -ceq 'DWord' -and
           $y.RegistryValueKind -ceq 'DWord'){
            $maxMb=[long]$x.DecimalDwordValue
            $warnMb=[long]$y.DecimalDwordValue
        }
    }
    $plausible=($maxMb -gt 0 -and $maxMb -le 51200 -and
                $warnMb -gt 0 -and $warnMb -le $maxMb -and
                ([decimal]($maxMb-$warnMb)*100 -ge [decimal]$maxMb*5))
    $established=($invalid.Count -eq 0 -and
                  $source -ne 'MicrosoftDocumentedDefaultAssumed' -and $pairComplete)
    $maxBytes=if($plausible){[long]$maxMb*1048576L}else{$null}
    $warnBytes=if($plausible){[long]$warnMb*1048576L}else{$null}
    $fits=($plausible -and $PlannedMaxArchivePstBytes -le [long]$warnBytes)
    $status=if($invalid.Count -gt 0){'InvalidRegistryValueKindNeedsManualReview'}
            elseif($source -eq 'MicrosoftDocumentedDefaultAssumed'){
                'MicrosoftDocumentedDefaultsAssumedNotMachineVerified'
            }elseif(-not $pairComplete){'PartialRegistryOverrideNeedsManualReview'}
            elseif(-not $plausible){'RegistryLimitsOutsideConservativeRangeNeedsReview'}
            elseif(-not $fits){'PlannedPstExceedsReadOnlyWarnLimitBlocked'}
            else{'ConfiguredUnicodePstLimitCompatibleForecastOnly'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.PstLimitDecision.1'
        Source=$source
        Status=$status
        RegistryPolicyValues=$PolicyProbe
        RegistryUserValues=$UserProbe
        InvalidRegistryValues=@($invalid.ToArray())
        EffectiveConfiguredPairFound=$established
        AssumedMicrosoftDefaultMaxLargeFileSizeMiB=51200
        AssumedMicrosoftDefaultWarnLargeFileSizeMiB=48640
        EffectiveMaxLargeFileSizeMiB=if($plausible){$maxMb}else{$null}
        EffectiveWarnLargeFileSizeMiB=if($plausible){$warnMb}else{$null}
        EffectiveMaxLargeFileSizeBytes=$maxBytes
        EffectiveWarnLargeFileSizeBytes=$warnBytes
        PlannedArchivePstMaximumBytes=[long]$PlannedMaxArchivePstBytes
        PlannedSafetyMarginBytes=[long]$PlannedSafetyMarginBytes
        ForecastMaximumBelowObservedWarnLimit=if($established){[bool]$fits}else{$null}
        DefaultPstLimitOnlyAssumed=($source -eq 'MicrosoftDocumentedDefaultAssumed')
        CurrentPstUnicodeFormatVerified=$false
        OutlookPolicyApplicationVerified=$false
        RegistryModified=$false
        UnlimitedPstSizeEnabled=$false
        CapacityProvenForRealPstWrites=$false
        RequiresManualReview=($status -cne 'ConfiguredUnicodePstLimitCompatibleForecastOnly')
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7sPriorYearInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Inventory,
        [Parameter(Mandatory=$true)][long]$ExpectedScopeCandidateItems,
        [Parameter(Mandatory=$true)][string]$ExpectedSourcePst
    )
    if([string]$Inventory.Schema -cne '2.6.5-BW4k7r.Pop3YearDistributionCapacityReadOnly.1' -or
       [string]$Inventory.Status -cnotin @('FullObservedPOP3YearDistributionReadOnlyCapacityForecastOnly',
           'FullReadOnlyYearDistributionWithDateFallbackNeedsReview') -or
       -not [bool]$Inventory.YearDistributionComplete -or
       -not [bool]$Inventory.AllCandidateItemsEnumerated -or
       [long]$Inventory.ScopeCandidateItemsTotal -ne $ExpectedScopeCandidateItems -or
       [long]$Inventory.CandidateItemsExamined -ne $ExpectedScopeCandidateItems -or
       [string]$Inventory.SourcePst -ine $ExpectedSourcePst -or
       [bool]$Inventory.MailMovedOrDeleted -or [bool]$Inventory.WriterPermit -or
       [bool]$Inventory.ProductionReady -or
       -not [bool]$Inventory.OriginalSEM001Unknown0x00010000StillBlocked){
        throw 'BW4k7s previous BW4k7r result is partial, mismatched, or unsafe.'
    }
    $sum=0L;$mail=0L;$keys=New-Object 'System.Collections.Generic.HashSet[int]'
    $rows=@($Inventory.YearDistribution)
    foreach($r in $rows){
        $y=[int]$r.Year
        if(-not $keys.Add($y) -or $y -lt 1990 -or $y -gt 2100 -or
           [string]$r.Coverage -cne 'FullyEnumeratedObservedMetadata' -or
           [bool]$r.ArchiveYearEligible -ne ($y -lt [int]$Inventory.ArchiveBeforeYear) -or
           -not [bool]$r.NoArchiveFileCreated){
            throw 'BW4k7s previous year distribution is inconsistent.'
        }
        $count=[long]$r.InboxMailItems+[long]$r.SentItemsMailItems+[long]$r.UserFolderMailItems
        if([long]$r.TotalMailItems -ne $count -or $count -le 0){throw 'BW4k7s bad previous year counts.'}
        $sum+=$count
        if([bool]$r.ArchiveYearEligible){$mail+=$count}
    }
    if($sum -ne [long]$Inventory.MailItemsDated -or
       $sum -ne [long]$Inventory.MailItemsObserved -or
       $sum+[long]$Inventory.NonMailItemsObserved -ne $ExpectedScopeCandidateItems -or
       [long]$Inventory.MailItemsUndated -ne 0){
        throw 'BW4k7s prior year/mail/non-mail totals do not reconcile.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.OperatorProvidedYearPlanCrosscheck.1'
        Status='InternallyConsistentButNotCryptographicallySealed'
        ObservedYears=@($rows | Sort-Object Year)
        EligibleArchiveYears=@($rows | Where-Object {$_.ArchiveYearEligible} | Sort-Object Year)
        EligibleArchiveMailItems=$mail
        AllObservedMailItems=$sum
        NonMailItemsExpected=[long]$Inventory.NonMailItemsObserved
        CryptographicallyBoundToCurrentPst=$false
        VerifiedAgainstImmutablePstSnapshot=$false
        ActualPstArchivesCreated=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
