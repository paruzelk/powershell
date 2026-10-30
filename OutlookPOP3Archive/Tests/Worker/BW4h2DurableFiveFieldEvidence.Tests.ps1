#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4fFreshFixtureScope265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4h1PostMoveFieldDrift265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4h2DurableFiveFieldEvidence265.ps1')
    $script:id='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:sub="OPA265 BW4e1 FRESH TEST $script:id"
    $script:body="OPA265 BW4e1 disposable synthetic test. `r`n`r`nTestId: $script:id `r`n"
    $script:sender='sender@example.invalid'
    $script:ticks=[long]639287965390000000
    $script:bodyHash=Get-OPA265BW4h1FieldDigest -Text $script:body
    $script:valid=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4h2.ImmutableFiveFieldEvidence.1'
        TestId=$script:id
        ProfileName='Outlook'
        PstPath='C:\Temp\source.pst'
        StoreId='00000000F00D'
        FolderEntryId='00000000AABB'
        ItemEntryId='00000000CCDD'
        InternetMessageId='<fixture123@example.invalid>'
        SearchKeySha256=('a'*64)
        ContentFingerprintSha256=(Get-OPA265BW4h1ContentHash -Subject $script:sub -SenderEmailAddress $script:sender -Body $script:body -Size 8760 -ReceivedUtcTicks $script:ticks)
        SubjectLength=$script:sub.Length
        SubjectUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $script:sub)
        SenderEmailAddressLength=$script:sender.Length
        SenderEmailAddressUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $script:sender)
        BodyLength=$script:body.Length
        BodyUtf8Sha256=$script:bodyHash
        BodyCR=([regex]::Matches($script:body,'`r')).Count
        BodyLF=([regex]::Matches($script:body,'`n')).Count
        Size=[long]8760
        ReceivedUtcTicks=$script:ticks
        ReceivedUtcTicksSha256=(Get-OPA265BW4h1FieldDigest -Text ($script:ticks.ToString([Globalization.CultureInfo]::InvariantCulture)))
        AttachmentCount=0
        CapturedUtc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
Describe 'BW4h2 strict immutable five field witness schema' {
    BeforeEach { $script:x=$script:valid.PSObject.Copy() }
    It 'accepts exact 25-field source witness' {
        (Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id) | Should -BeTrue
    }
    It 'denies missing source size' {
        $script:x.PSObject.Properties.Remove('Size')
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies extra unknown production permit' {
        $script:x | Add-Member NoteProperty CanInvokeMove $true
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies changed TestId or reused fixture' {
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId '49bf59da-6d84-4e36-8b6d-0d9857b8eed1' } | Should -Throw
    }
    It 'denies missing InternetMessageId' {
        $script:x.InternetMessageId=''
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies malformed Body digest' {
        $script:x.BodyUtf8Sha256='not64'
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies missing before-Move UTC timestamp' {
        $script:x.CapturedUtc='broken'
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies attachments on future synthetic fixture' {
        $script:x.AttachmentCount=1
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies automatic retries from forged evidence' {
        $script:x.AutomaticRetryAllowed=$true
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
    It 'denies production-ready evidence' {
        $script:x.ProductionReady=$true
        { Assert-OPA265BW4h2Evidence -Evidence $script:x -TestId $script:id } | Should -Throw
    }
}
Describe 'BW4h2 per-field independent comparison never approves Move retry' {
    BeforeEach {
        $script:before=$script:valid.PSObject.Copy()
        $script:after=$script:valid.PSObject.Copy()
        $script:after.PstPath='C:\Temp\OPA265-BW4g-98bef8170fb5478ab86933f02fda59d3.pst'
        $script:after.ItemEntryId='00000000EF01'
        $script:after.FolderEntryId='00000000FA02'
        $script:after.StoreId='00000000FB03'
    }
    It 'reports all original five fields unchanged without claiming PST binary equality' {
        $d=Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after
        $d.Status | Should -BeExactly 'AllFiveFieldsMatchReadOnly'
        $d.FourNonSizeFieldsMatch | Should -BeTrue
        $d.FullMAPIByteEqualityProven | Should -BeFalse
        $d.CanRetryMove | Should -BeFalse
    }
    It 'reports exact source 8760 versus destination 8798 +38 metadata delta with four matching fields' {
        $script:after.Size=[long]8798
        $script:after.ContentFingerprintSha256=Get-OPA265BW4h1ContentHash -Subject $script:sub -SenderEmailAddress $script:sender -Body $script:body -Size 8798 -ReceivedUtcTicks $script:ticks
        $d=Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after
        $d.Status | Should -BeExactly 'OnlyMAPIMessageSizeChangedManualReview'
        $d.DestinationMinusSourceSize | Should -Be 38
        $d.FourNonSizeFieldsMatch | Should -BeTrue
        $d.CompositeFingerprintMatches | Should -BeFalse
        $d.CanWriteHistoricalJournal | Should -BeFalse
    }
    It 'distinguishes changed Body from simple +38 size-only drift' {
        $script:after.Size=[long]8798
        $script:after.BodyUtf8Sha256=('b'*64)
        $d=Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after
        $d.Status | Should -BeExactly 'ContentFieldDriftNeedsManualReview'
        $d.BodyMatches | Should -BeFalse
    }
    It 'distinguishes changed sender address digest' {
        $script:after.SenderEmailAddressUtf8Sha256=('b'*64)
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).SenderEmailAddressMatches | Should -BeFalse
    }
    It 'distinguishes changed received time' {
        $script:after.ReceivedUtcTicks=$script:ticks+1
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).ReceivedUtcTicksMatches | Should -BeFalse
    }
    It 'distinguishes changed subject hash' {
        $script:after.SubjectUtf8Sha256=('c'*64)
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).SubjectMatches | Should -BeFalse
    }
    It 'blocks InternetMessageId drift before field comparison' {
        $script:after.InternetMessageId='<other@example.invalid>'
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).Status | Should -BeExactly 'BlockedIdentityDrift'
    }
    It 'blocks PR_SEARCH_KEY drift' {
        $script:after.SearchKeySha256=('f'*64)
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).IdentityMatches | Should -BeFalse
    }
    It 'blocks composite SHA mismatch when all five component digests are unchanged' {
        $script:after.ContentFingerprintSha256=('f'*64)
        (Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after).Status | Should -BeExactly 'BlockedCompositeFingerprintInconsistency'
    }
    It 'refuses invalid or altered source witness TestId' {
        $script:before.TestId='invalid'
        {Compare-OPA265BW4h2FieldEvidence -Before $script:before -After $script:after} | Should -Throw
    }
}
Describe 'BW4h2 write-once source witness path and persistent no-overwrite rule' {
    BeforeAll { $script:oldAppData=$env:LOCALAPPDATA }
    AfterAll { $env:LOCALAPPDATA=$script:oldAppData }
    It 'uses a deterministic per-user path for the TestId' {
        $p=Get-OPA265BW4h2EvidencePath -TestId $script:id -LocalAppData 'C:\Temp'
        $p | Should -BeExactly ('C:\Temp\OutlookPOP3Archive-BW4h2-FieldEvidence\fixture-'+$script:id+'.json')
    }
    It 'denies bad GUID in evidence pathname' {
        {Get-OPA265BW4h2EvidencePath -TestId '../old'} | Should -Throw
    }
    It 'denies path redirection outside original local AppData' {
        $env:LOCALAPPDATA=$TestDrive
        {Write-OPA265BW4h2OnceEvidence -Evidence $script:valid -TestId $script:id -EvidencePath 'C:\Windows\Temp\other.json'} | Should -Throw
    }
    It 'creates a durable UTF8-BOM evidence file once, second write is blocked' {
        $env:LOCALAPPDATA=$TestDrive
        $p=Get-OPA265BW4h2EvidencePath -TestId $script:id
        $written=Write-OPA265BW4h2OnceEvidence -Evidence $script:valid -TestId $script:id -EvidencePath $p
        [IO.File]::Exists($written) | Should -BeTrue
        ([IO.File]::ReadAllBytes($written)[0]) | Should -Be 239
        $loaded=Get-Content -LiteralPath $written -Raw -Encoding UTF8 | ConvertFrom-Json
        (Assert-OPA265BW4h2Evidence -Evidence $loaded -TestId $script:id) | Should -BeTrue
        {Write-OPA265BW4h2OnceEvidence -Evidence $script:valid -TestId $script:id -EvidencePath $p} | Should -Throw
    }
}
Describe 'BW4h2 automation and history safety static gate' {
    BeforeAll {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4h2DurableFieldEvidence.ps1'
        $script:code=[IO.File]::ReadAllText($p)
    }
    It 'has no source or destination Outlook Move invocation' {
        $script:code | Should -Not -Match '(?i)\$mail\.Move\('
        $script:code | Should -Not -Match '(?i)\$.*\.Move\('
    }
    It 'does not create one-shot claim or modify journal files' {
        $script:code | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
        $script:code | Should -Not -Match 'Write-OPAOperationJournal'
    }
    It 'requires full prior BW4h independent read-only reconciliation before destination comparison' {
        $script:code | Should -Match 'Test-OPA265BW4hIndependentReconciliationReadOnly\.ps1'
        $script:code | Should -Match 'ExpectedSourceEvidenceSha256'
    }
    It 'forbids retrospective evidence capture once any prior attempt claim exists' {
        $script:code | Should -Match 'cannot take a source-before-Move snapshot after any one-shot claim exists'
    }
    It 'retains exact historic seven-file and one-Intent preflight on each source capture' {
        $script:code | Should -Match 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly\.ps1'
        $script:code | Should -Match 'HistoricJournalPhase'
    }
}
