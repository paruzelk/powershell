#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7eImmutableSemanticSnapshot265.ps1')
    function New-BW4k7eSyntheticReport {
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7d.IndependentRecipientFlagsSourceReadOnly.1'
            Status='ExactAttachment1KRecipientsAndUserStateDoubleReadVerifiedNoMove'
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            OriginalSourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
            VerifiedDecisionSha256='29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6'
            OriginalThreeMoveClaimsUnchanged=$true
            RecipientCount=1;ToCount=1;CcCount=0;BccCount=0
            RecipientDigestSha256='11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024'
            UserStateDigestSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
            UnRead=$false;MapiFlags=65555;SemanticReadAndAttachMask=17
            SourceAttachmentCount=1;IndependentReadOnlyWitnesses=2
            RawRecipientAddressesExposed=$false
            SourceSemanticSnapshotPersisted=$false
            FuturePostMoveContentVerified=$false
            FullProductionSignificantFlagMaskProven=$false
            OutlookMoveExecuted=$false
            AttemptClaimWritten=$false;WriterPermit=$false
            CanRetryMove=$false;ProductionReady=$false
        }
    }
}
Describe 'BW4k7e exact immutable source recipient/state snapshot' {
    BeforeEach {
        $script:r=New-BW4k7eSyntheticReport
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:root)
    }
    It 'accepts exact read-only BW4k7d original results' {
        (Assert-OPA265BW4k7eExactReview -Review $script:r) | Should -BeTrue
    }
    It 'pins original operator size decision immutable SHA' {
        $script:r.VerifiedDecisionSha256=('a'*64)
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'pins exactly original To/Cc/Bcc recipient cardinality' {
        $script:r.CcCount=1
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'pins original recipient SHA-256' {
        $script:r.RecipientDigestSha256=('a'*64)
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'pins original significant user-state SHA-256' {
        $script:r.UserStateDigestSha256=('a'*64)
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'pins MAPI flags and semantic mask' {
        $script:r.MapiFlags=65539
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'pins original source EntryId' {
        $script:r.OriginalSourceEntryId='ANOTHER'
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'requires both independently stable Outlook witnesses' {
        $script:r.IndependentReadOnlyWitnesses=1
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*independently observed*'
    }
    It 'requires original three real Move claims unchanged' {
        $script:r.OriginalThreeMoveClaimsUnchanged=$false
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*prior chain*'
    }
    It 'never accepts a hidden prior Move or Claim' {
        $script:r.AttemptClaimWritten=$true
        {Assert-OPA265BW4k7eExactReview -Review $script:r} | Should -Throw '*forbidden*'
    }
    It 'creates only scoped receipt metadata with no raw recipients' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $s.RecipientDigestSha256 | Should -BeExactly $script:r.RecipientDigestSha256
        $s.UserStateDigestSha256 | Should -BeExactly $script:r.UserStateDigestSha256
        $s.PSObject.Properties.Name | Should -Not -Contain 'Address'
        $s.RawRecipientAddressesPersisted | Should -BeFalse
        $s.WriterPermit | Should -BeFalse
    }
    It 'validates the newly generated snapshot schema' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        (Assert-OPA265BW4k7eSnapshot -Snapshot $s -Review $script:r) | Should -BeTrue
    }
    It 'rejects extra fields that could grant an unsafe permission' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $s | Add-Member -NotePropertyName AllowMove -NotePropertyValue $true
        {Assert-OPA265BW4k7eSnapshot -Snapshot $s -Review $script:r} | Should -Throw '*extra/missing*'
    }
    It 'refuses modified recipient evidence inside a snapshot' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $s.RecipientDigestSha256=('a'*64)
        {Assert-OPA265BW4k7eSnapshot -Snapshot $s -Review $script:r} | Should -Throw '*record pin*'
    }
    It 'refuses a forged source-content rebaseline flag' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $s.SourceContentRebaselineAllowed=$true
        {Assert-OPA265BW4k7eSnapshot -Snapshot $s -Review $script:r} | Should -Throw '*unauthorized*'
    }
    It 'refuses invented postmove comparison in source-only snapshot' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $s.PostMoveRecipientComparisonProven=$true
        {Assert-OPA265BW4k7eSnapshot -Snapshot $s -Review $script:r} | Should -Throw '*unauthorized*'
    }
    It 'requires the exact local AppData destination path' {
        {Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId 'wrong' -LocalAppData $script:root} | Should -Throw '*exact original*'
    }
    It 'writes BOM JSON one time and returns its independent SHA256' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId $script:r.TestId -LocalAppData $script:root
        $w=Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root
        $w.SnapshotSha256 | Should -Match '^[a-f0-9]{64}$'
        $bytes=[IO.File]::ReadAllBytes($path)
        @($bytes[0],$bytes[1],$bytes[2]) -join ',' | Should -BeExactly '239,187,191'
    }
    It 'refuses a duplicate snapshot write even with identical payload' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId $script:r.TestId -LocalAppData $script:root
        $null=Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root
        {Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root} | Should -Throw
    }
    It 'refuses redirected snapshot write path' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        {Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path (Join-Path $script:root 'different.json') -LocalAppData $script:root} | Should -Throw '*redirected*'
    }
    It 'can independently Verify recorded source SHA' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId $script:r.TestId -LocalAppData $script:root
        $w=Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root
        $v=Read-OPA265BW4k7eSnapshotVerified -Review $script:r -ExpectedSnapshotSha256 $w.SnapshotSha256 -LocalAppData $script:root
        $v.Status | Should -BeExactly 'OriginalRecipientStateSnapshotVerifiedNoWriterPermit'
        $v.WriterPermit | Should -BeFalse
    }
    It 'fails closed when independent SHA is altered' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId $script:r.TestId -LocalAppData $script:root
        $null=Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root
        {Read-OPA265BW4k7eSnapshotVerified -Review $script:r -ExpectedSnapshotSha256 ('a'*64) -LocalAppData $script:root} | Should -Throw '*missing or immutable*'
    }
    It 'fails closed if current source recipient digest changes after capture' {
        $s=New-OPA265BW4k7eSnapshot -Review $script:r
        $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $script:r.SuiteId -TestId $script:r.TestId -LocalAppData $script:root
        $w=Write-OPA265BW4k7eSnapshotOnce -Snapshot $s -Review $script:r -Path $path -LocalAppData $script:root
        $script:r.RecipientDigestSha256=('b'*64)
        {Read-OPA265BW4k7eSnapshotVerified -Review $script:r -ExpectedSnapshotSha256 $w.SnapshotSha256 -LocalAppData $script:root} | Should -Throw '*independently observed*'
    }
    It 'ensures controller is read-only in Review and no MailItem.Move ever' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7eSemanticSourceSnapshot.ps1'
        $s=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $s | Should -Match "Mode -ceq 'Review'"
        $s | Should -Match 'WhatIfNoSemanticSnapshotNoMove'
        $s | Should -Match "Mode -ceq 'Verify'"
        $s | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\s*\('
        $s | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
    }
    It 'requires new explicit Capture approval instead of reusing size decision' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7eSemanticSourceSnapshot.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'ConfirmCaptureOnce'
        $s | Should -Match 'CAPTURE EXACT BW4K7E RECIPIENT STATE SOURCE NO MOVE'
        $s | Should -Match 'SupportsShouldProcess=\$true'
    }
}
