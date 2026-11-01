#requires -Version 5.1
# BW4j5: synthetic deterministic read-only reconciliation plus separate receipts.
# Receipts NEVER authorize another move, production, or historical journal edits.
. (Join-Path $PSScriptRoot 'BW4j4SyntheticOneShot265.ps1')
function Get-OPA265BW4j5FieldWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [switch]$Destination)
    [void](Assert-OPA265BW4j4Fixture -Mail $Mail -Case $Case -SuiteId $SuiteId)
    $attachments=New-Object 'System.Collections.Generic.List[object]'
    foreach($a in @($Mail.Attachments)){
        if($a -isnot [pscustomobject] -or
            [string]$a.FileName -cnotmatch '^[A-Za-z0-9._-]{1,128}$' -or
            [long]$a.ByteCount -lt 1024 -or [long]$a.ByteCount -gt 262144) {
            throw 'BW4j5 invalid by-value attachment metadata.'
        }
        $bytes=[Convert]::FromBase64String([string]$a.BytesBase64)
        $sha=Get-OPA265BW4jSha256 -Bytes $bytes
        if($bytes.Length -ne [int]$a.ByteCount -or $sha -cne [string]$a.Sha256){
            throw 'BW4j5 synthetic attachment actual decoded bytes or hash differ.'
        }
        $attachments.Add([pscustomobject][ordered]@{
            FileName=[string]$a.FileName
            ByteCount=[long]$bytes.Length
            Sha256=$sha
        })
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j5.SyntheticFieldWitness.1'
        SuiteId=$SuiteId
        TestId=[string]$Mail.TestId
        CaseName=[string]$Mail.CaseName
        StoreId=$(if($Destination){'SYNTH-TARGET-'+$SuiteId}else{'SYNTH-SOURCE-'+$SuiteId})
        EntryId=$(if($Destination){[string]$Mail.DestinationEntryId}else{[string]$Mail.SourceEntryId})
        InternetMessageId=[string]$Mail.InternetMessageId
        SubjectSha256=(Get-OPA265BW4jTextHash -Value ([string]$Mail.Subject))
        SenderSha256=(Get-OPA265BW4jTextHash -Value ([string]$Mail.SenderEmailAddress))
        BodySha256=(Get-OPA265BW4jTextHash -Value ([string]$Mail.Body))
        HtmlBodySha256=(Get-OPA265BW4jTextHash -Value ([string]$Mail.HtmlBody))
        ReceivedUtcTicks=[long]$Mail.ReceivedUtcTicks
        Size=[long]($Mail.SourceSize + $(if($Destination){[long]$Mail.InjectedDestinationSizeDelta}else{[long]0}))
        Attachments=@($attachments.ToArray())
        IsSyntheticEmulation=$true
        OutlookMAPIObserved=$false
        ProductionReady=$false
    }
}
function Compare-OPA265BW4j5FieldWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    if($Before.Schema -cne '2.6.5-BW4j5.SyntheticFieldWitness.1' -or
       $After.Schema -cne '2.6.5-BW4j5.SyntheticFieldWitness.1' -or
       $Before.IsSyntheticEmulation -isnot [bool] -or -not $Before.IsSyntheticEmulation -or
       $After.IsSyntheticEmulation -isnot [bool] -or -not $After.IsSyntheticEmulation -or
       $Before.OutlookMAPIObserved -isnot [bool] -or $Before.OutlookMAPIObserved -or
       $After.OutlookMAPIObserved -isnot [bool] -or $After.OutlookMAPIObserved -or
       $Before.ProductionReady -isnot [bool] -or $Before.ProductionReady -or
       $After.ProductionReady -isnot [bool] -or $After.ProductionReady){
        throw 'BW4j5 only compares verified synthetic witnesses.'
    }
    $identity=($Before.TestId -ceq $After.TestId -and
        $Before.SuiteId -ceq $After.SuiteId -and
        $Before.CaseName -ceq $After.CaseName -and
        $Before.InternetMessageId -ceq $After.InternetMessageId -and
        $Before.EntryId -cne $After.EntryId -and
        $Before.StoreId -cne $After.StoreId)
    $subject=($Before.SubjectSha256 -ceq $After.SubjectSha256)
    $sender=($Before.SenderSha256 -ceq $After.SenderSha256)
    $body=($Before.BodySha256 -ceq $After.BodySha256)
    $html=($Before.HtmlBodySha256 -ceq $After.HtmlBodySha256)
    $time=([long]$Before.ReceivedUtcTicks -eq [long]$After.ReceivedUtcTicks)
    $attachments=($Before.Attachments.Count -eq $After.Attachments.Count)
    if($attachments){for($i=0;$i -lt $Before.Attachments.Count;$i++){
        $a=$Before.Attachments[$i];$b=$After.Attachments[$i]
        if($a.FileName -cne $b.FileName -or
            [long]$a.ByteCount -ne [long]$b.ByteCount -or
            $a.Sha256 -cne $b.Sha256){$attachments=$false}
    }}
    $content=($subject -and $sender -and $body -and $html -and $time -and $attachments)
    $delta=[long]$After.Size-[long]$Before.Size
    $status=if(-not $identity){'BLOCKED_SyntheticIdentityOrStoreDrift'}
        elseif(-not $content){'BLOCKED_SyntheticContentOrAttachmentDrift'}
        elseif($delta -ne 0){'SyntheticModeledSizeOnlyDriftNeedsRealOutlookVerification'}
        else{'SyntheticFieldsMatchNoRealMAPIProof'}
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j5.SyntheticWitnessComparison.1'
        Status=$status
        TestId=$Before.TestId
        IdentityMatches=[bool]$identity
        SubjectMatches=[bool]$subject
        SenderMatches=[bool]$sender
        BodyMatches=[bool]$body
        HtmlBodyMatches=[bool]$html
        ReceivedTimeMatches=[bool]$time
        AttachmentsMatch=[bool]$attachments
        SourceSize=[long]$Before.Size
        SyntheticDestinationSize=[long]$After.Size
        SyntheticSizeDelta=[long]$delta
        RealOutlookMAPIObserved=$false
        AutomaticSizeDriftAcceptanceAllowed=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
function Get-OPA265BW4j5Reconciliation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
          [Parameter(Mandatory=$true)][string]$TestId)
    $state=Get-OPA265BW4j4State -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256 -TestId $TestId
    if($state.State -cnotin @('MoveObservedAwaitIndependentReconciliation','ReceiptExistsReadOnlyVerify')){
        throw ('BW4j5 reconciliation blocked by crash/duplicate state: '+$state.State)
    }
    $m=Get-OPA265BW4j4Manifest -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256
    $row=Get-OPA265BW4j4FixtureRow -Manifest $m -TestId $TestId
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
    $paths=Get-OPA265BW4j4Paths -Root $root -TestId $TestId
    if((Get-OPA265BW4j4FileSha -Path $paths.Target) -cne [string]$row.Seal.SourceJsonSha256){
        throw 'BW4j5 moved synthetic mail file differs from independent source manifest SHA256.'
    }
    $claimSha=Get-OPA265BW4j4FileSha -Path $paths.Claim
    $claim=Get-Content -LiteralPath $paths.Claim -Raw -Encoding UTF8 | ConvertFrom-Json
    if($claim.Schema -cne '2.6.5-BW4j4.IrreversibleSyntheticAttemptClaim.1' -or
        $claim.TestId -cne $TestId -or
        $claim.SuiteId -cne $m.Plan.SuiteId -or
        $claim.OriginalManifestSha256 -cne $ExpectedManifestSha256 -or
        $claim.OriginalSourceSha256 -cne [string]$row.Seal.SourceJsonSha256 -or
        $claim.OneAttemptOnly -isnot [bool] -or -not $claim.OneAttemptOnly -or
        $claim.AutomaticRetryAllowed -isnot [bool] -or $claim.AutomaticRetryAllowed -or
        $claim.ProductionReady -isnot [bool] -or $claim.ProductionReady) {
        throw 'BW4j5 synthetic durable claim changed or unsafe.'
    }
    $mail=Get-Content -LiteralPath $paths.Target -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4j4Fixture -Mail $mail -Case $row.Case -SuiteId $m.Plan.SuiteId)
    # Each field digest is RECOMPUTED independently; only Size +38 is a
    # modeled input, NOT empirical evidence for five real Outlook messages.
    $before=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $m.Plan.SuiteId
    $after=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $m.Plan.SuiteId -Destination
    $comparison=Compare-OPA265BW4j5FieldWitness -Before $before -After $after
    if($comparison.Status -cne 'SyntheticModeledSizeOnlyDriftNeedsRealOutlookVerification' -or
       -not $comparison.IdentityMatches -or -not $comparison.AttachmentsMatch -or
       [long]$comparison.SyntheticSizeDelta -ne [long]$row.Seal.ExpectedSyntheticDestinationDelta){
        throw 'BW4j5 blocked: synthetic contents/size are inconsistent with original model.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j5.IndependentSyntheticReadOnlyReconciliation.1'
        Status='SyntheticMoveConfirmedModelOnlyNoOutlookProof'
        SuiteId=$m.Plan.SuiteId
        TestId=$TestId
        CaseName=$row.Case.Name
        OriginalManifestSha256=$ExpectedManifestSha256
        OriginalSourceJsonSha256=$row.Seal.SourceJsonSha256
        OriginalOneShotClaimSha256=$claimSha
        SubjectMatches=$comparison.SubjectMatches
        SenderMatches=$comparison.SenderMatches
        BodyMatches=$comparison.BodyMatches
        HtmlBodyMatches=$comparison.HtmlBodyMatches
        ReceivedTimeMatches=$comparison.ReceivedTimeMatches
        AttachmentsMatch=$comparison.AttachmentsMatch
        SourceSize=$comparison.SourceSize
        SyntheticDestinationSize=$comparison.SyntheticDestinationSize
        SyntheticSizeDelta=$comparison.SyntheticSizeDelta
        OutlookMoveExecuted=$false
        RealMAPIFieldEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
function Write-OPA265BW4j5ReceiptOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
          [Parameter(Mandatory=$true)][string]$TestId)
    $reconciled=Get-OPA265BW4j5Reconciliation -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256 -TestId $TestId
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
    $p=Get-OPA265BW4j4Paths -Root $root -TestId $TestId
    if([IO.File]::Exists($p.Receipt)){throw 'BW4j5 reconciliation receipt already exists; no rewrite.'}
    $receipt=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4j5.ImmutableSyntheticReconciliationReceipt.1'
        Comparison=$reconciled
        ReconciledUtc=[datetime]::UtcNow.ToString('o')
        SourceZeroDestinationOne=$true
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
    $hash=Write-OPA265BW4j4JsonOnce -Path $p.Receipt -Value $receipt
    [pscustomobject][ordered]@{
        Status='SyntheticReceiptWrittenOnceNoOutlookMove'
        TestId=$TestId
        ReceiptSha256=$hash
        ReceiptPath=$p.Receipt
        CanRetryMove=$false
        ProductionReady=$false
    }
}
function Get-OPA265BW4j5SuiteSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256)
    $m=Get-OPA265BW4j4Manifest -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256
    $items=New-Object 'System.Collections.Generic.List[object]'
    $confirmed=0;$blocked=0;$pending=0
    foreach($case in @($m.Plan.Cases)){
        $status=Get-OPA265BW4j4State -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256 -TestId $case.TestId
        $result='';$receiptSha=''
        if($status.State -cnotlike 'BLOCKED_*' -and
           $status.State -ceq 'ReceiptExistsReadOnlyVerify'){
            $proof=Get-OPA265BW4j5Reconciliation -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256 -TestId $case.TestId
            $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
            $p=Get-OPA265BW4j4Paths -Root $root -TestId $case.TestId
            $receiptSha=Get-OPA265BW4j4FileSha -Path $p.Receipt
            $receipt=Get-Content -LiteralPath $p.Receipt -Raw -Encoding UTF8 | ConvertFrom-Json
            if($receipt.Schema -cne '2.6.5-BW4j5.ImmutableSyntheticReconciliationReceipt.1' -or
                $receipt.Comparison.OriginalOneShotClaimSha256 -cne $proof.OriginalOneShotClaimSha256 -or
                $receipt.Comparison.OriginalManifestSha256 -cne $ExpectedManifestSha256 -or
                $receipt.Comparison.TestId -cne $case.TestId -or
                $receipt.CanRetryMove -isnot [bool] -or $receipt.CanRetryMove -or
                $receipt.CanWriteHistoricalJournal -isnot [bool] -or $receipt.CanWriteHistoricalJournal -or
                $receipt.ProductionReady -isnot [bool] -or $receipt.ProductionReady){
                throw 'BW4j5 synthetic receipt differs from sealed reconciliation.'
            }
            $result='SyntheticReceiptIndependentlyReverified';$confirmed++
        } elseif($status.State -like 'BLOCKED_*' -or
                  $status.State -ceq 'ClaimedSourceStillPresentNeverRetry'){
            $result='BLOCKED_DoNotRetry';$blocked++
        }else{$result='PendingOrUnreconciled';$pending++}
        $items.Add([pscustomobject][ordered]@{
            CaseName=$case.Name
            TestId=$case.TestId
            State=$status.State
            Result=$result
            ReceiptSha256=$receiptSha
        })
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j5.SyntheticSuiteSummary.1'
        SuiteId=$m.Plan.SuiteId
        Total=5
        IndependentlyReconciled=$confirmed
        Blocked=$blocked
        PendingOrUnreconciled=$pending
        Items=@($items.ToArray())
        AllFiveSyntheticItemsReconciled=($confirmed -eq 5)
        OutlookUsed=$false
        RealPstTouched=$false
        OriginalHistoricalIntentTouched=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
