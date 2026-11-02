#requires -Version 5.1
# BW4k0 operator preflight for a selected disposable mail in Outlook.
# Source review/capture only; never creates mail, sends, moves, deletes or mounts PST.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('ReviewSelected','CaptureSelected')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmSourceCaptureOnce
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4k0 requires native Windows PowerShell 5.1 STA.'
}
if (($Mode -ceq 'CaptureSelected') -ne [bool]$ConfirmSourceCaptureOnce) {
    throw 'BW4k0 CaptureSelected needs explicit -ConfirmSourceCaptureOnce; ReviewSelected forbids it.'
}
if ($ExpectedPlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]::IsNullOrWhiteSpace($ExpectedProfileName)) {
    throw 'BW4k0 exact plan SHA256 and profile are required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k0SelectedScope265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Validate original immutable five-case BW4j plan'
$app=$null
$ns=$null
try {
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if (-not [IO.File]::Exists($planPath) -or
        (([IO.File]::GetAttributes($planPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        (Get-Item -LiteralPath $planPath).Length -gt 16384) {
        throw 'BW4k0 original five-case plan unavailable or unsafe.'
    }
    if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256) {
        throw 'BW4k0 original plan SHA256 mismatch.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    $case=$null
    $hits=0
    foreach ($row in @($plan.Cases)) {
        if ([string]$row.TestId -ceq $TestId) {
            $case=$row
            $hits++
        }
    }
    if ($hits -ne 1 -or $null -eq $case) {
        throw 'BW4k0 selected TestId must occur exactly once in pinned five-case plan.'
    }
    $stage='Attach to already-running Outlook and validate active POP3 store'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) {throw 'BW4k0 requires Outlook to be running.'}
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne $ExpectedProfileName) {
        throw 'BW4k0 wrong active Outlook profile.'
    }
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$source.Store.GetDefaultFolder(6)
    if ($null -eq $inbox -or [string]$inbox.StoreID -cne [string]$source.StoreId) {
        throw 'BW4k0 unable to identify exact POP3 Inbox.'
    }
    $stage='Inspect exactly one operator-selected synthetic POP3 Inbox mail'
    $explorer=$app.ActiveExplorer()
    if ($null -eq $explorer) {throw 'BW4k0 requires an active Outlook Explorer selection.'}
    $selection=$explorer.Selection
    if ($null -eq $selection -or [int]$selection.Count -ne 1) {
        throw 'BW4k0 requires selecting exactly one test mail in Outlook.'
    }
    $mail=$selection.Item(1)
    $scope=Assert-OPA265BW4k0SelectedMail -Mail $mail -Case $case -ExpectedStoreId ([string]$source.StoreId) -ExpectedInboxFolderEntryId ([string]$inbox.EntryID) -SelectionCount ([int]$selection.Count)
    $stage='Perform independent BW4j two-read witness and historical safety gate'
    $reviewMode=if ($Mode -ceq 'CaptureSelected') {'SourceCapture'} else {'SourceReview'}
    $opts=@{
        Mode=$reviewMode
        SuiteId=$SuiteId
        TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        SourcePst=$SourcePst
        ExpectedProfileName=$ExpectedProfileName
        SourceFolderEntryId=$scope.SourceFolderEntryId
        SourceEntryId=$scope.SourceEntryId
    }
    if ($Mode -ceq 'CaptureSelected') {$opts.ConfirmCaptureSourceOnce=$true}
    $result=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4jSuiteReadOnly.ps1') @opts
    $expectedStatus=if ($Mode -ceq 'CaptureSelected') {'OneSourceFixtureEvidenceCapturedNoMove'} else {'SourceFixtureReadOnlyReadyNoMove'}
    if ($null -eq $result -or [string]$result.Status -cne $expectedStatus -or
        [bool]$result.OutlookMoveExecuted -or [bool]$result.ProductionReady) {
        throw 'BW4k0 independent BW4j review/capture returned an unsafe status.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k0.SelectedRealOutlookPreflight.1'
        Status=if ($Mode -ceq 'CaptureSelected') {'OriginalSourceWitnessCapturedNoMove'} else {'ExactSelectedDisposableSourceReviewedNoMove'}
        SuiteId=$SuiteId
        TestId=$TestId
        CaseName=$case.Name
        SourceEntryId=$scope.SourceEntryId
        SourceFolderEntryId=$scope.SourceFolderEntryId
        OriginalPlanSha256=$ExpectedPlanSha256
        EvidencePath=[string]$result.EvidencePath
        EvidenceSha256=[string]$result.EvidenceSha256
        SourceSize=[long]$result.SourceSize
        AttachmentCount=[int]$result.AttachmentCount
        HistoricalSevenHashesUnchanged=[bool]$result.HistoricalSevenHashesUnchanged
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
} catch {
    throw ('BW4k0 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No MailItem.Move or historical journal write was attempted.')
} finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
