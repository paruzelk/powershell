#requires -Version 5.1
# BW4k7i: original Attachment1K read-only flag classification and Outlook restart proof.
# Stores one NEW immutable baseline outside PST/Claim/journal. Never runs MailItem.Move.
. (Join-Path $PSScriptRoot 'BW4k7hPostMoveFlagAttribution265.ps1')

function Assert-OPA265BW4k7iExactPriorAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Audit,
          [Parameter(Mandatory=$true)][psobject]$Attribution)
    $checks=@{
        Schema='2.6.5-BW4k7g.IndependentPostMoveSemanticAudit.1'
        Status='SourceZeroDestinationOneSemanticMismatchRequiresManualReview'
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        VerifiedOneShotClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        VerifiedSourceSemanticSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
        DestinationEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
        DestinationFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B82800000'
        SourceMessageIdMatches='0';DestinationMessageIdMatches='1'
        OriginalSourceSize='8122'
        IndependentDestinationContentReads='2'
        IndependentDestinationSemanticReads='2'
    }
    foreach($field in $checks.Keys){
        if([string]$Audit.$field -cne [string]$checks[$field]){
            throw ('BW4k7i prior independent audit changed: '+$field)
        }
    }
    foreach($field in @('SubjectMatches','SenderMatches','BodyMatches','HtmlBodyMatches',
        'ReceivedUtcTicksMatches','AttachmentBytesAndSha256Match',
        'SearchKeyAndInternetMessageIdentityMatches','FullRecipientSha256Matches',
        'SignificantReadAttachBitsMatch')){
        if($Audit.$field -isnot [bool] -or -not $Audit.$field){
            throw ('BW4k7i previously matched content/recipient field changed: '+$field)
        }
    }
    foreach($field in @('FullUserStateSha256Matches','AllCapturedContentMatched',
        'PhysicalPstDurabilityProven','FullProductionSignificantFlagCoverageProven',
        'OutlookMoveExecutedByAudit','AutomaticRetryAllowed','WriterPermit',
        'ProductionReady')){
        if($Audit.$field -isnot [bool] -or $Audit.$field){
            throw ('BW4k7i semantic mismatch must remain an unresolved gate: '+$field)
        }
    }
    $aChecks=@{
        Schema='2.6.5-BW4k7h.IndependentPostMoveFlagAttribution.1'
        Status='OnlyRawPrMessageFlagsChangedAllCapturedUserFieldsMatch'
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        OriginalOneShotClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        OriginalRecipientStateSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
        DestinationEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
        SourceMessageIdMatches='0';DestinationMessageIdMatches='1'
        OriginalMapiFlags='65555';DestinationMapiFlags='17'
        ChangedMapiFlagsXor='65538'
        OriginalMapiFlagsHex='0x00010013';DestinationMapiFlagsHex='0x00000011'
        ChangedMapiFlagsXorHex='0x00010002'
        OriginalUserStateSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
        ReconstructedOriginalFlagsUserStateSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
        IndependentDestinationSemanticReads='2'
    }
    foreach($field in $aChecks.Keys){
        if([string]$Attribution.$field -cne [string]$aChecks[$field]){
            throw ('BW4k7i independent raw MAPI flag attribution changed: '+$field)
        }
    }
    if(@($Attribution.ChangedFlagBitValues).Count -ne 2 -or
       [int]$Attribution.ChangedFlagBitValues[0] -ne 2 -or
       [int]$Attribution.ChangedFlagBitValues[1] -ne 65536){
        throw 'BW4k7i changed flags must be ONLY 0x00000002 and 0x00010000.'
    }
    foreach($field in @('SignificantReadAttachBitsMatch','CapturedOutlookUserFieldsMatchExcludingRawMapiFlags',
        'OnlyRawMapiFlagsChanged')){
        if($Attribution.$field -isnot [bool] -or -not $Attribution.$field){
            throw ('BW4k7i captured user fields or READ/HASATTACH changed: '+$field)
        }
    }
    foreach($field in @('ChangedRawFlagBitsSemanticallyClassified','PriorObservedMismatchMayBeReclassifiedAutomatically',
        'RawRecipientAddressesExposed','ExistingClaimRewritten','OriginalEvidenceRewritten',
        'OutlookMoveExecuted','WriterPermit','AutomaticRetryAllowed','ProductionReady')){
        if($Attribution.$field -isnot [bool] -or $Attribution.$field){
            throw ('BW4k7i cannot override prior failed audit or write Claim: '+$field)
        }
    }
    if($Attribution.DestinationUserStateSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Attribution.DestinationUserStateSha256 -ceq [string]$Attribution.OriginalUserStateSha256){
        throw 'BW4k7i raw original mismatch unexpectedly resolved.'
    }
    return $true
}

function Get-OPA265BW4k7iProcessIdentity {
    [CmdletBinding()]
    param()
    $all=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($all.Count -ne 1){
        throw 'BW4k7i requires exactly one local OUTLOOK.EXE process.'
    }
    $p=$all[0]
    $start=[datetime]$p.StartTime
    if([int]$p.Id -lt 1 -or $start.ToUniversalTime().Ticks -lt 1){
        throw 'BW4k7i cannot read reliable original Outlook process identity.'
    }
    [pscustomobject][ordered]@{
        ProcessId=[int]$p.Id
        StartUtcTicks=[long]$start.ToUniversalTime().Ticks
    }
}

function Get-OPA265BW4k7iBaselinePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $null=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId -LocalAppData $LocalAppData
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7'){
        throw 'BW4k7i immutable baseline path only for the exact original Attachment1K.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7i-ReopenBaselines') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}

function New-OPA265BW4k7iBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Audit,
          [Parameter(Mandatory=$true)][psobject]$Attribution,
          [Parameter(Mandatory=$true)][psobject]$OutlookProcess)
    [void](Assert-OPA265BW4k7iExactPriorAudit -Audit $Audit -Attribution $Attribution)
    if(@($OutlookProcess.PSObject.Properties.Name).Count -ne 2 -or
       [int]$OutlookProcess.ProcessId -lt 1 -or
       [long]$OutlookProcess.StartUtcTicks -lt 1){
        throw 'BW4k7i invalid immutable Outlook process identity.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7i.ImmutablePreReopenReadOnlyArchiveBaseline.1'
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        ClaimSha256=[string]$Audit.VerifiedOneShotClaimSha256
        OriginalRecipientStateSnapshotSha256=[string]$Audit.VerifiedSourceSemanticSnapshotSha256
        SourceMessageIdMatches=[int]$Audit.SourceMessageIdMatches
        DestinationMessageIdMatches=[int]$Audit.DestinationMessageIdMatches
        DestinationEntryId=[string]$Audit.DestinationEntryId
        DestinationFolderEntryId=[string]$Audit.DestinationFolderEntryId
        DestinationSize=[long]$Audit.DestinationSize
        DestinationUserStateSha256=[string]$Attribution.DestinationUserStateSha256
        ReconstructedOriginalFlagsUserStateSha256=[string]$Attribution.ReconstructedOriginalFlagsUserStateSha256
        OriginalMapiFlags=[int]$Attribution.OriginalMapiFlags
        DestinationMapiFlags=[int]$Attribution.DestinationMapiFlags
        ChangedMapiFlagsXor=[int]$Attribution.ChangedMapiFlagsXor
        ChangedFlagBitValues=@([int]2,[int]65536)
        AllCapturedOutlookUserFieldsMatched=$true
        ArchiveBodyAttachmentRecipientsMatched=$true
        SignificantReadAndAttachMaskMatched=$true
        OriginalAuditMismatchStillRequiresReview=$true
        OriginalOutlookProcessId=[int]$OutlookProcess.ProcessId
        OriginalOutlookProcessStartUtcTicks=[long]$OutlookProcess.StartUtcTicks
        CapturedUtc=[datetime]::UtcNow.ToString('o')
        OriginalClaimOrJournalModified=$false
        OutlookMailMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}

function Assert-OPA265BW4k7iBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Baseline)
    $fields=@('Schema','SuiteId','TestId','ClaimSha256','OriginalRecipientStateSnapshotSha256',
        'SourceMessageIdMatches','DestinationMessageIdMatches','DestinationEntryId',
        'DestinationFolderEntryId','DestinationSize','DestinationUserStateSha256',
        'ReconstructedOriginalFlagsUserStateSha256','OriginalMapiFlags','DestinationMapiFlags',
        'ChangedMapiFlagsXor','ChangedFlagBitValues','AllCapturedOutlookUserFieldsMatched',
        'ArchiveBodyAttachmentRecipientsMatched','SignificantReadAndAttachMaskMatched',
        'OriginalAuditMismatchStillRequiresReview','OriginalOutlookProcessId',
        'OriginalOutlookProcessStartUtcTicks','CapturedUtc','OriginalClaimOrJournalModified',
        'OutlookMailMoveExecuted','AutomaticRetryAllowed','ProductionReady')
    if(@($Baseline.PSObject.Properties.Name).Count -ne $fields.Count){
        throw 'BW4k7i immutable baseline has missing or extra fields.'
    }
    foreach($f in $fields){
        if($Baseline.PSObject.Properties.Name -cnotcontains $f){throw ('BW4k7i missing '+$f)}
    }
    $fixed=@{
        Schema='2.6.5-BW4k7i.ImmutablePreReopenReadOnlyArchiveBaseline.1'
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        ClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        OriginalRecipientStateSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
        SourceMessageIdMatches='0';DestinationMessageIdMatches='1'
        DestinationEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
        DestinationFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B82800000'
        OriginalMapiFlags='65555';DestinationMapiFlags='17';ChangedMapiFlagsXor='65538'
        ReconstructedOriginalFlagsUserStateSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
    }
    foreach($f in $fixed.Keys){
        if([string]$Baseline.$f -cne [string]$fixed[$f]){
            throw ('BW4k7i baseline immutable pin differs: '+$f)
        }
    }
    if(@($Baseline.ChangedFlagBitValues).Count -ne 2 -or
       [int]$Baseline.ChangedFlagBitValues[0] -ne 2 -or
       [int]$Baseline.ChangedFlagBitValues[1] -ne 65536){
        throw 'BW4k7i unexpected MAPI flag bits in immutable baseline.'
    }
    foreach($f in @('AllCapturedOutlookUserFieldsMatched','ArchiveBodyAttachmentRecipientsMatched',
        'SignificantReadAndAttachMaskMatched','OriginalAuditMismatchStillRequiresReview')){
        if($Baseline.$f -isnot [bool] -or -not $Baseline.$f){
            throw ('BW4k7i original qualified evidence invalid: '+$f)
        }
    }
    foreach($f in @('OriginalClaimOrJournalModified','OutlookMailMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady')){
        if($Baseline.$f -isnot [bool] -or $Baseline.$f){
            throw ('BW4k7i forbidden evidence permit: '+$f)
        }
    }
    if([long]$Baseline.DestinationSize -ne 8168 -or
       [string]$Baseline.DestinationUserStateSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Baseline.DestinationUserStateSha256 -ceq [string]$Baseline.ReconstructedOriginalFlagsUserStateSha256 -or
       [int]$Baseline.OriginalOutlookProcessId -lt 1 -or
       [long]$Baseline.OriginalOutlookProcessStartUtcTicks -lt 1){
        throw 'BW4k7i destination evidence, Size, or Outlook process witness invalid.'
    }
    $date=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Baseline.CapturedUtc,[ref]$date)){
        throw 'BW4k7i immutable baseline time invalid.'
    }
    return $true
}

function Write-OPA265BW4k7iBaselineOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Baseline,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    [void](Assert-OPA265BW4k7iBaseline -Baseline $Baseline)
    $path=Get-OPA265BW4k7iBaselinePath -SuiteId $Baseline.SuiteId -TestId $Baseline.TestId -LocalAppData $LocalAppData
    $root=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($path))
    $parent=[IO.Path]::GetDirectoryName($path)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7i baseline root cannot be a reparse point.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7i baseline parent cannot be a reparse point.'
    }
    $enc=New-Object Text.UTF8Encoding($true)
    $bytes=$enc.GetBytes((ConvertTo-Json -InputObject $Baseline -Depth 5))
    if($bytes.Length -gt 16384){throw 'BW4k7i immutable baseline too large.'}
    $bom=$enc.GetPreamble()
    $stream=$null
    try{
        $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bom,0,$bom.Length)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }finally{if($null -ne $stream){$stream.Dispose()}}
    [pscustomobject][ordered]@{
        BaselinePath=$path
        BaselineSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Read-OPA265BW4k7iBaselineVerified {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ExpectedBaselineSha256,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $path=Get-OPA265BW4k7iBaselinePath -SuiteId '74912f94-d523-4856-9efd-d5528a92426f' -TestId '87e72fd0-9e77-4098-a403-cbe99870b9e7' -LocalAppData $LocalAppData
    if($ExpectedBaselineSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.File]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedBaselineSha256){
        throw 'BW4k7i immutable baseline missing or SHA-256 differs. NEVER overwrite.'
    }
    $baseline=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4k7iBaseline -Baseline $baseline)
    return $baseline
}

function Compare-OPA265BW4k7iAfterReopen {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Baseline,
          [Parameter(Mandatory=$true)][psobject]$Reopened,
          [Parameter(Mandatory=$true)][psobject]$ReopenedProcess)
    [void](Assert-OPA265BW4k7iBaseline -Baseline $Baseline)
    [void](Assert-OPA265BW4k7iBaseline -Baseline $Reopened)
    if([int]$ReopenedProcess.ProcessId -lt 1 -or
       [long]$ReopenedProcess.StartUtcTicks -lt 1){
        throw 'BW4k7i reopened Outlook process identity invalid.'
    }
    if([long]$ReopenedProcess.StartUtcTicks -le [long]$Baseline.OriginalOutlookProcessStartUtcTicks){
        throw 'BW4k7i Outlook MUST be fully closed and reopened after baseline capture.'
    }
    if([int]$Baseline.OriginalOutlookProcessId -eq [int]$ReopenedProcess.ProcessId -and
       [long]$Baseline.OriginalOutlookProcessStartUtcTicks -eq [long]$ReopenedProcess.StartUtcTicks){
        throw 'BW4k7i original Outlook process still active; reopen gate blocked.'
    }
    $fields=@('Schema','SuiteId','TestId','ClaimSha256',
        'OriginalRecipientStateSnapshotSha256','SourceMessageIdMatches',
        'DestinationMessageIdMatches','DestinationEntryId','DestinationFolderEntryId',
        'DestinationSize','DestinationUserStateSha256','ReconstructedOriginalFlagsUserStateSha256',
        'OriginalMapiFlags','DestinationMapiFlags','ChangedMapiFlagsXor',
        'AllCapturedOutlookUserFieldsMatched','ArchiveBodyAttachmentRecipientsMatched',
        'SignificantReadAndAttachMaskMatched','OriginalAuditMismatchStillRequiresReview',
        'OriginalClaimOrJournalModified','OutlookMailMoveExecuted','AutomaticRetryAllowed','ProductionReady')
    foreach($field in $fields){
        if([string]$Baseline.$field -cne [string]$Reopened.$field){
            throw ('BW4k7i archived evidence differs after actual Outlook restart: '+$field)
        }
    }
    if((@($Baseline.ChangedFlagBitValues) -join ',') -cne (@($Reopened.ChangedFlagBitValues) -join ',')){
        throw 'BW4k7i PR_MESSAGE_FLAGS changed after Outlook restart.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7i.AfterOutlookRestartSemanticReview.1'
        Status='ReopenedOutlookSourceZeroDestinationOneCapturedSemanticsStableUnknownFlagStillBlocked'
        SuiteId=$Baseline.SuiteId;TestId=$Baseline.TestId
        OriginalProcessId=[int]$Baseline.OriginalOutlookProcessId
        ReopenedProcessId=[int]$ReopenedProcess.ProcessId
        OriginalProcessStartUtcTicks=[long]$Baseline.OriginalOutlookProcessStartUtcTicks
        ReopenedProcessStartUtcTicks=[long]$ReopenedProcess.StartUtcTicks
        ActualNewOutlookProcessObserved=$true
        SourceMessageIdMatches=0;DestinationMessageIdMatches=1
        DestinationEntryId=$Baseline.DestinationEntryId
        DestinationUserStateSha256=$Reopened.DestinationUserStateSha256
        ArchiveContentRecipientAttachmentShaStable=$true
        AllCapturedUserFieldsStable=$true
        RawMapiFlagsStableSinceBaseline=$true
        MessageFlagUnmodified0x00000002='DocumentedProviderModificationStateCleared'
        UnknownFlag0x00010000='UnspecifiedByReviewedMicrosoftTablesRequiresSeparateResearch'
        UnknownFlagWaived=$false
        HistoricalPostmoveMismatchAutomaticallyReclassified=$false
        OutlookArchiveReadAfterRealProcessRestart=$true
        PhysicalPstDurabilityFullyProven=$false
        OriginalClaimOrJournalModified=$false
        OutlookMailMoveExecuted=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
