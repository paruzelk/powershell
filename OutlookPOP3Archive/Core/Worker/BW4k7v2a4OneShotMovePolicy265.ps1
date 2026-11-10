#requires -Version 5.1
# BW4k7v2a4 isolated one-shot synthetic Move policy. No production dispatch.
. (Join-Path $PSScriptRoot 'BW4k7v2a1ExistingProfilePolicy265.ps1')

function Get-OPA265BW4k7v2a4Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    [void](Assert-OPA265BW4k7v2a1SuiteId -SuiteId $SuiteId)
    if($SuiteId -ceq '2c15cb7c-4c09-4bcf-bca1-9fec458af3a5'){
        throw 'BW4k7v2a4 old misrouted BW4k7v2a1 SuiteId is quarantined.'
    }
    if(-not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\\',[StringComparison]::Ordinal) -or
       -not [IO.Directory]::Exists($LocalAppData)){
        throw 'BW4k7v2a4 requires existing local non-UNC LOCALAPPDATA.'
    }
    $root=[IO.Path]::GetFullPath((Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7v2a4-OneShotMove'))
    $dir=Join-Path $root ('suite-'+$SuiteId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a4.Layout.1'
        SuiteId=$SuiteId;ProfileName='Outlook';Pop3SmtpAddress='info@stios.ru'
        Root=$root;SuiteDirectory=$dir
        PstPath=(Join-Path $dir ('OPA265-BW4k7v2a4-'+$SuiteId+'.pst'))
        IntentPath=(Join-Path $dir 'create-intent.json')
        ManifestPath=(Join-Path $dir 'pilot-premovemanifest.json')
        MoveClaimPath=(Join-Path $dir 'one-shot-move-claim.json')
        MoveReturnPath=(Join-Path $dir 'move-return-observation.json')
        TargetFolderName=('OPA265-BW4k7v2a4-'+$SuiteId)
        Subject=('OPA265-BW4k7v2a4-PILOT-'+$SuiteId)
        Body=('BW4k7v2a4 disposable default-Drafts Move test '+$SuiteId)
        Recipient='synthetic-recipient@example.invalid'
        WriterPermit=$false;ProductionReady=$false
    }
}

function Assert-OPA265BW4k7v2a4Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $correct=Get-OPA265BW4k7v2a4Layout -SuiteId ([string]$Layout.SuiteId) -LocalAppData $LocalAppData
    foreach($field in @('ProfileName','Pop3SmtpAddress','Root','SuiteDirectory',
        'PstPath','IntentPath','ManifestPath','MoveClaimPath','MoveReturnPath',
        'TargetFolderName','Subject','Body','Recipient')){
        if([string]$Layout.$field -cne [string]$correct.$field){
            throw ('BW4k7v2a4 forged layout '+$field)
        }
    }
    foreach($path in @($correct.Root,$correct.SuiteDirectory,$correct.PstPath)){
        if(([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) -and
            (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4k7v2a4 reparse point in suite path forbidden.'
        }
    }
    return $true
}

function Test-OPA265BW4k7v2a4StoreScope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ActualProfileName,
          [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$Accounts,
          [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$Stores,
          [Parameter(Mandatory=$true)][AllowEmptyString()][string]$DefaultStoreId,
          [switch]$TargetAttached)
    $scopeParams=@{
        Layout=$Layout;ActualProfileName=$ActualProfileName
        Accounts=$Accounts;Stores=$Stores;AllowTargetAttached=[bool]$TargetAttached
    }
    $base=Test-OPA265BW4k7v2a1ExistingProfileScope @scopeParams
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    foreach($r in @($base.ReasonCodes)){$reasons.Add([string]$r)}
    if([string]::IsNullOrWhiteSpace($DefaultStoreId)){$reasons.Add('DefaultStoreIdMissing')}
    $defaultMatches=@($Stores | Where-Object {
        $null -ne $_ -and [string]$_.StoreId -ceq $DefaultStoreId
    })
    if($defaultMatches.Count -ne 1){$reasons.Add('DefaultStoreNotUnique')}
    if($DefaultStoreId -ceq [string]$base.Pop3DeliveryStoreId){
        $reasons.Add('DefaultDraftsIsOriginalPop3DeliveryStore')
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a4.StoreScope.1'
        Approved=($reasons.Count -eq 0)
        ReasonCodes=@($reasons.ToArray())
        ProfileName=$ActualProfileName
        DefaultStoreId=$DefaultStoreId
        Pop3DeliveryStoreId=[string]$base.Pop3DeliveryStoreId
        TargetPstMatches=[int]$base.TestStoreCount
        DefaultDraftsWriteRequiresOperatorOptIn=$true
        OriginalPop3PstCannotBeDefaultDrafts=$true
        ProductionReady=$false;WriterPermit=$false
    }
}

function Get-OPA265BW4k7v2a4SemanticWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Snapshot)
    foreach($f in @('Subject','Body','To','Unread','Class')){
        if($Snapshot.PSObject.Properties.Name -cnotcontains $f -or
           $null -eq $Snapshot.PSObject.Properties[$f]){
            throw ('BW4k7v2a4 missing synthetic witness field '+$f)
        }
    }
    if([int]$Snapshot.Class -ne 43){throw 'BW4k7v2a4 witness must be MailItem Class=43.'}
    $record=[pscustomobject][ordered]@{
        Class=[int]$Snapshot.Class
        Subject=[string]$Snapshot.Subject
        Body=[string]$Snapshot.Body
        To=[string]$Snapshot.To
        Unread=[bool]$Snapshot.Unread
    }
    $text=ConvertTo-Json -InputObject $record -Compress -Depth 3
    $sha=Get-OPA265BW4k7v2a1Sha256 -Text $text
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a4.SyntheticWitness.1'
        SemanticSha256=$sha
        Class=[int]$record.Class
        Subject=[string]$record.Subject
        Body=[string]$record.Body
        To=[string]$record.To
        Unread=[bool]$record.Unread
        AttachmentCountExpected=0
        CompleteSEM001ProductionFieldsProven=$false
        UnknownRawMapiFlagsAutomaticallyWaived=$false
        WriterPermit=$false;ProductionReady=$false
    }
}

function Test-OPA265BW4k7v2a4MoveReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Manifest,
        [Parameter(Mandatory=$true)][object]$Claim,
        [ValidateRange(0,99)][int]$SourceMatches,
        [ValidateRange(0,99)][int]$DestinationMatches,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$DestinationWitnesses,
        [bool]$OutlookRestartConfirmed
    )
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if([string]$Claim.SuiteId -cne [string]$Manifest.SuiteId -or
       [string]$Claim.SourceEntryId -cne [string]$Manifest.SourceEntryId -or
       [string]$Claim.SourceStoreId -cne [string]$Manifest.SourceStoreId -or
       [string]$Claim.TargetStoreId -cne [string]$Manifest.TargetStoreId -or
       [string]$Claim.TargetFolderId -cne [string]$Manifest.TargetFolderId){
        $issues.Add('ClaimAndOriginalManifestDoNotMatch')
    }
    if(-not $OutlookRestartConfirmed){$issues.Add('IndependentOutlookRestartNotConfirmed')}
    if($SourceMatches -ne 0){$issues.Add('SourceNotZero')}
    if($DestinationMatches -ne 1){$issues.Add('DestinationNotOne')}
    if($DestinationWitnesses.Count -ne $DestinationMatches){
        $issues.Add('DestinationBoundedReadIncomplete')
    }
    if($DestinationMatches -eq 1 -and $DestinationWitnesses.Count -eq 1){
        $w=$DestinationWitnesses[0]
        if([string]$w.SemanticSha256 -cne [string]$Manifest.SemanticSha256){
            $issues.Add('SemanticWitnessMismatch')
        }
        if([string]$w.ParentStoreId -cne [string]$Manifest.TargetStoreId -or
           [string]$w.ParentFolderId -cne [string]$Manifest.TargetFolderId){
            $issues.Add('DestinationFolderOrStoreMismatch')
        }
    }
    $status='ManualReviewRequiredUnreconciled'
    if($issues.Count -eq 0){$status='OneShotMoveReconciledSyntheticContentMatchSEM001ManualReview'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a4.OneShotMoveReconciliation.1'
        Status=$status
        Reasons=@($issues.ToArray())
        OriginalSourceCount=$SourceMatches
        DestinationCount=$DestinationMatches
        OutlookRestartConfirmed=$OutlookRestartConfirmed
        SyntheticSemanticMatch=($issues.Count -eq 0)
        OriginalMoveMayBeRetried=$false
        SEM001RiskAcceptanceAutomaticallyGranted=$false
        ProductionIntegrityProven=$false
        WriterPermit=$false;ProductionReady=$false
    }
}