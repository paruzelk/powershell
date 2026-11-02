#requires -Version 5.1
# BW4k7d: exact original Attachment1K full COM recipients and user-visible state,
# twice read-only; pinned immutable BW4k7c decision SHA, three prior Claims.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7d STOP: requires Windows PowerShell 5.1 STA.'
}
if($ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
   $SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
   $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
   $ExpectedProfileName -cne 'Outlook'){
    throw 'BW4k7d STOP: exact verified source-size decision/profile pins required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7dRecipientFlagWitness265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Independent BW4k7c original semantic decision SHA verification'
$app=$null;$ns=$null
try{
    $verifyArgs=@{
        Mode='Verify';SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName
    }
    $v1=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7cExactSourceSizeDecision.ps1') @verifyArgs
    if([string]$v1.Status -cne 'ExactSourceSizeManualDecisionIndependentlyVerifiedNoWriterPermit' -or
       [string]$v1.DecisionSha256 -cne $ExpectedDecisionSha256 -or
       [bool]$v1.WriterPermit -or [bool]$v1.CanRetryMove -or [bool]$v1.ProductionReady){
        throw 'BW4k7d original independent decision verification not established.'
    }
    $stage='Re-open only exact original Outlook POP3 store and source MailItem'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7d Outlook profile changed.'
    }
    $scope=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$scope.Store.GetDefaultFolder(6)
    $folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $mailId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
    if(-not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.EntryID) -Expected $folderId)){
        throw 'BW4k7d exact original Inbox EntryId changed.'
    }
    $mail=$ns.GetItemFromID($mailId,[string]$scope.StoreId)
    if($null -eq $mail -or [int]$mail.Class -ne 43 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$mail.Parent.EntryID) -Expected $folderId) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$mail.Parent.StoreID) -Expected ([string]$scope.StoreId))){
        throw 'BW4k7d exact original source MailItem/store/folder mismatch.'
    }
    $stage='Two live read-only recipient and significant flag observations'
    $witnessArgs=@{
        Mail=$mail;SuiteId=$SuiteId;TestId=$TestId;SourceEntryId=$mailId
    }
    $a=Get-OPA265BW4k7dLiveWitness @witnessArgs
    $b=Get-OPA265BW4k7dLiveWitness @witnessArgs
    [void](Assert-OPA265BW4k7dStableWitness -First $a -Second $b)
    if($b.AttachmentCount -ne 1 -or -not $b.HasAttachment -or
       [int]$b.MapiFlags -ne 65555){
        throw 'BW4k7d original one attachment and MAPI flags no longer match pinned evidence.'
    }
    $stage='Revalidate all historical evidence and exact decision after Outlook reads'
    $v2=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7cExactSourceSizeDecision.ps1') @verifyArgs
    if([string]$v2.Status -cne [string]$v1.Status -or
       [string]$v2.DecisionSha256 -cne $ExpectedDecisionSha256 -or
       [bool]$v2.WriterPermit -or [bool]$v2.ProductionReady){
        throw 'BW4k7d historical or manual decision verification changed after read.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7d.IndependentRecipientFlagsSourceReadOnly.1'
        Status='ExactAttachment1KRecipientsAndUserStateDoubleReadVerifiedNoMove'
        SuiteId=$SuiteId;TestId=$TestId
        OriginalSourceEntryId=$mailId
        VerifiedDecisionSha256=$ExpectedDecisionSha256
        OriginalThreeMoveClaimsUnchanged=$true
        RecipientCount=[int]$b.RecipientCount
        ToCount=[int]$b.ToCount
        CcCount=[int]$b.CcCount
        BccCount=[int]$b.BccCount
        RecipientDigestSha256=[string]$b.RecipientDigestSha256
        UserStateDigestSha256=[string]$b.UserStateDigestSha256
        UnRead=[bool]$b.UnRead
        MapiFlags=[int]$b.MapiFlags
        SemanticReadAndAttachMask=[int]$b.SignificantReadAndAttachMask
        SourceAttachmentCount=[int]$b.AttachmentCount
        IndependentReadOnlyWitnesses=2
        RawRecipientAddressesExposed=$false
        SourceSemanticSnapshotPersisted=$false
        FuturePostMoveContentVerified=$false
        FullProductionSignificantFlagMaskProven=$false
        OutlookMoveExecuted=$false
        AttemptClaimWritten=$false
        WriterPermit=$false
        CanRetryMove=$false
        ProductionReady=$false
        NextAction='Stop;NoNewMove;ReviewRecipientAndFlagWitness;DesignImmutablePreMoveSemanticSnapshot'
    }
}catch{
    throw ('BW4k7d STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, no source recapture, no historic journal or decision modification.')
}finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
