#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4hIndependentReconciliation265.ps1')
    $script:id='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:source='C:\Temp\source.pst'
    $script:dest='C:\Temp\OPA265-BW4g-98bef8170fb5478ab86933f02fda59d3.pst'
    $script:folder='00000000CF6192C80751D449BAE3D80D38AE509582800000'
    $script:sourceId='00000000E1878292411BC64291BD506DCEFD2A35C4613C00'
    $script:msgId='<000301dd66ed$53e67f40$fbb37dc0$@stios.ru>'
    $script:claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4g.ImmutableOneShotClaim.1'
        TestId=$script:id
        CandidateReviewId=[guid]::NewGuid().ToString('D')
        SourcePst=$script:source
        SourceEntryId=$script:sourceId
        InternetMessageId=$script:msgId
        DestinationPst=$script:dest
        DestinationFolderEntryId=$script:folder
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $script:params=@{
        TestId=$script:id;SourcePst=$script:source;DestinationPst=$script:dest
        SourceEntryId=$script:sourceId;DestinationFolderEntryId=$script:folder
        InternetMessageId=$script:msgId
    }
}
Describe 'BW4h immutable original BW4g claim read-only verification' {
    BeforeEach {
        $script:current=$script:claim.PSObject.Copy()
    }
    It 'accepts exactly the once-only real BW4g persisted claim layout' {
        (Assert-OPA265BW4hClaim -Claim $script:current @script:params) | Should -BeTrue
    }
    It 'rejects missing claim schema property' {
        $script:current.PSObject.Properties.Remove('Utc')
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects unexpected extra property' {
        $script:current | Add-Member NoteProperty CanRetryMove $true
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects mismatching source PST' {
        $script:current.SourcePst='C:\Temp\someone-else.pst'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects mismatching destination PST' {
        $script:current.DestinationPst='C:\Temp\other.pst'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects mismatching original source EntryID' {
        $script:current.SourceEntryId='004466'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects unknown target destination folder' {
        $script:current.DestinationFolderEntryId='0011'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects changed original InternetMessageId' {
        $script:current.InternetMessageId='<wrong@example.invalid>'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects any already-enabled replay flag' {
        $script:current.AutomaticRetryAllowed=$true
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects any claim of production readiness' {
        $script:current.ProductionReady=$true
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects fake non-boolean automatic retry' {
        $script:current.AutomaticRetryAllowed='false'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects invalid one-shot review GUID' {
        $script:current.CandidateReviewId='bad'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects missing UTC in durable claim' {
        $script:current.Utc='invalid'
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects noncanonical operator TestId' {
        $script:current.TestId=$script:id.ToUpperInvariant()
        {Assert-OPA265BW4hClaim -Claim $script:current @script:params} | Should -Throw
    }
    It 'rejects any destination that has not exactly the GUID scoped PST filename' {
        $invalid=$script:params.Clone()
        $invalid.DestinationPst='C:\Temp\wrong.pst'
        {Assert-OPA265BW4hClaim -Claim $script:current @invalid} | Should -Throw
    }
}
Describe 'BW4h independent source/destination read-only classification' {
    BeforeEach {
        $script:dec=@{
            SourceMatches=0;DestinationMatches=1;DestinationFolderCount=1
            DestinationEntryIdMatches=$true;InternetMessageIdMatches=$true
            FixtureMatches=$true;SearchKeyMatches=$true
            ContentFingerprintMatches=$true;HistoricalEvidenceUnchanged=$true
            ClaimUnchanged=$true
        }
    }
    It 'only passes an exact one-destination zero-source fully matching read-only observation' {
        $d=Get-OPA265BW4hReadOnlyDecision @script:dec
        $d.Status | Should -BeExactly 'IndependentOutlookReadOnlyMoveReconciled'
        $d.ReadOnlyReconciliationPassed | Should -BeTrue
        $d.CanRetryMove | Should -BeFalse
        $d.PhysicalPstDurabilityProven | Should -BeFalse
        $d.FullMAPIByteEqualityProven | Should -BeFalse
    }
    It 'blocks one remaining source copy' {
        $script:dec.SourceMatches=1
        (Get-OPA265BW4hReadOnlyDecision @script:dec).Status | Should -BeExactly 'MoveNotIndependentlyConfirmedNeedsManualReview'
    }
    It 'blocks absent destination message' {
        $script:dec.DestinationMatches=0
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'blocks duplicated destination InternetMessageId' {
        $script:dec.DestinationMatches=2
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'blocks any extra message in test-only destination folder' {
        $script:dec.DestinationFolderCount=2
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'blocks different destination EntryID' {
        $script:dec.DestinationEntryIdMatches=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'blocks different InternetMessageId' {
        $script:dec.InternetMessageIdMatches=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'blocks non-fixture destination email' {
        $script:dec.FixtureMatches=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).ReadOnlyReconciliationPassed | Should -BeFalse
    }
    It 'reports cross-PST MAPI SearchKey drift without silently accepting' {
        $script:dec.SearchKeyMatches=$false
        $d=Get-OPA265BW4hReadOnlyDecision @script:dec
        $d.Status | Should -BeExactly 'MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview'
        $d.ReadOnlyReconciliationPassed | Should -BeFalse
        $d.CanRetryMove | Should -BeFalse
    }
    It 'reports cross-PST content or size fingerprint drift without silently accepting' {
        $script:dec.ContentFingerprintMatches=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).Status | Should -BeExactly 'MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview'
    }
    It 'blocks historical seven hashes or visible journal drift' {
        $script:dec.HistoricalEvidenceUnchanged=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).Status | Should -BeExactly 'BlockedHistoricalOrClaimEvidenceDrift'
    }
    It 'blocks original one-shot claim drift' {
        $script:dec.ClaimUnchanged=$false
        (Get-OPA265BW4hReadOnlyDecision @script:dec).Status | Should -BeExactly 'BlockedHistoricalOrClaimEvidenceDrift'
    }
}
Describe 'BW4h no mutation and no retry code inspection' {
    BeforeAll {
        $src=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW4hIndependentReconciliationReadOnly.ps1'
        $script:code=[IO.File]::ReadAllText($src)
    }
    It 'contains no MailItem.Move invocation' {
        $script:code | Should -Not -Match '\$mail\.Move\('
        $script:code | Should -Not -Match '\$direct\.Move\('
    }
    It 'contains no irreversible attempt claim creation' {
        $script:code | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
    }
    It 'contains no operation journal mutation function' {
        $script:code | Should -Not -Match 'Write-OPAOperationJournal'
        $script:code | Should -Not -Match 'Add-Content'
    }
    It 'uses a bounded exact InternetMessageId Restrict for both PSTs' {
        $script:code | Should -Match 'Items.Restrict\(\$restriction\)'
        $script:code | Should -Match '\$destFolder.Items.Restrict\(\$restriction\)'
    }
    It 'reads the original durable claim and checks its SHA256 before and after' {
        $script:code | Should -Match 'claimBefore=.*Get-FileHash'
        $script:code | Should -Match 'claimAfter=.*Get-FileHash'
    }
}
