#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k2IndependentRealMoveAudit265.ps1')
    function Get-OPA265BW4k2SyntheticInput {
        $tid=[guid]::NewGuid().ToString('D')
        $sid=[guid]::NewGuid().ToString('D')
        $hash='a'*64
        $original=[pscustomobject]@{
            CaseName='PlainSmall';FolderEntryId='SOURCE-FOLDER'
            InternetMessageId='<synthetic@example.test>';Size=6768
        }
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
            SuiteId=$sid;TestId=$tid;CaseName='PlainSmall'
            PlanSha256=$hash;EvidenceSetSha256=('b'*64)
            SourceEvidenceSha256=('c'*64)
            SourcePst='C:\source.pst';SourceEntryId='SOURCE-ITEM'
            SourceFolderEntryId='SOURCE-FOLDER'
            InternetMessageId='<synthetic@example.test>'
            DestinationPst='C:\target.pst'
            DestinationFolderEntryId='TARGET-FOLDER'
            ClaimUtc=[datetime]::UtcNow.ToString('o')
            RealOutlookOneShot=$true
            AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
        $audit=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.IndependentSourceDestinationReadOnly.1'
            Status='OnlyMAPIMessageSizeChangedNeedsManualReview'
            SuiteId=$sid;TestId=$tid;CaseName='PlainSmall'
            OriginalSuitePlanSha256=$hash;OriginalSourceEvidenceSha256=('c'*64)
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            SourceSize=6768;DestinationSize=6806;DeltaSize=38
            SubjectMatches=$true;SenderMatches=$true;BodyMatches=$true
            HtmlBodyMatches=$true;ReceivedUtcTicksMatches=$true
            AttachmentsMatch=$true;HistoricalSevenHashesUnchanged=$true
            FullMAPIByteEqualityProven=$false;PhysicalPstDurabilityProven=$false
            OutlookMoveExecutedByThisAudit=$false;CanRetryMove=$false
            CanWriteHistoricalJournal=$false;ProductionReady=$false
        }
        [pscustomobject]@{
            SuiteId=$sid;TestId=$tid
            Original=$original;Claim=$claim;Audit=$audit
            Params=@{
                Original=$original;SuiteId=$sid;TestId=$tid
                PlanSha256=$hash;FiveSealSha256=('b'*64)
                SourceEvidenceSha256=('c'*64)
                SourcePst='C:\source.pst';DestinationPst='C:\target.pst'
                DestinationFolderEntryId='TARGET-FOLDER';SourceEntryId='SOURCE-ITEM'
            }
            AuditParams=@{
                Original=$original;SuiteId=$sid;TestId=$tid
                PlanSha256=$hash;SourceEvidenceSha256=('c'*64)
            }
        }
    }
}
Describe 'BW4k2 immutable BW4k1 claim and independent double read-only comparison' {
    BeforeEach {
        $script:input=Get-OPA265BW4k2SyntheticInput
    }
    It 'verifies correctly pinned one-shot claim with exact 17 fields' {
        (Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params) | Should -BeTrue
    }
    It 'rejects claim with foreign suite' {
        $script:input.Claim.SuiteId=[guid]::NewGuid().ToString('D')
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*SuiteId*'
    }
    It 'rejects tampered exact original evidence digest' {
        $script:input.Claim.SourceEvidenceSha256='d'*64
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*SourceEvidenceSha256*'
    }
    It 'rejects a destination folder mismatch' {
        $script:input.Claim.DestinationFolderEntryId='OTHER-FOLDER'
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*DestinationFolderEntryId*'
    }
    It 'rejects foreign PST path in recorded claim' {
        $script:input.Claim.DestinationPst='C:\foreign.pst'
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*PST path mismatch*'
    }
    It 'rejects automatic retry permission' {
        $script:input.Claim.AutomaticRetryAllowed=$true
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*unsafe real move claim flags*'
    }
    It 'rejects production readiness' {
        $script:input.Claim.ProductionReady=$true
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*unsafe real move claim flags*'
    }
    It 'rejects unparseable claim time' {
        $script:input.Claim.ClaimUtc='not-a-time'
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*ClaimUtc*'
    }
    It 'rejects extra claim property' {
        $script:input.Claim|Add-Member -NotePropertyName ExtraPermit -NotePropertyValue $true
        {Assert-OPA265BW4k2Claim -Claim $script:input.Claim @script:input.Params} | Should -Throw '*schema property count differs*'
    }
    It 'accepts only reportable exact source-zero destination-one and unaccepted +38' {
        (Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams) | Should -BeTrue
    }
    It 'rejects destination-zero' {
        $script:input.Audit.DestinationMessageIdMatches=0
        {Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams} | Should -Throw '*source-zero/target-one*'
    }
    It 'rejects altered HTML' {
        $script:input.Audit.HtmlBodyMatches=$false
        {Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams} | Should -Throw '*HtmlBodyMatches*'
    }
    It 'rejects incorrect +38 size arithmetic' {
        $script:input.Audit.DeltaSize=39
        {Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams} | Should -Throw '*size arithmetic*'
    }
    It 'rejects status that implicitly accepts changed size' {
        $script:input.Audit.Status='AllCheckedFieldsMatchReadOnly'
        {Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams} | Should -Throw '*drift status differs*'
    }
    It 'rejects audit that claims PST crash durability was proved' {
        $script:input.Audit.PhysicalPstDurabilityProven=$true
        {Assert-OPA265BW4k2IndependentAudit -Audit $script:input.Audit @script:input.AuditParams} | Should -Throw '*overclaimed proof*'
    }
    It 'requires two independent readings to be identical' {
        $second=$script:input.Audit|ConvertTo-Json -Depth 6|ConvertFrom-Json
        (Assert-OPA265BW4k2StableAudits -First $script:input.Audit -Second $second) | Should -BeTrue
        $second.DestinationSize=6807
        {Assert-OPA265BW4k2StableAudits -First $script:input.Audit -Second $second} | Should -Throw '*DestinationSize*'
    }
    It 'only invokes the independent review and never invokes a writer or Move' {
        $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k2IndependentReadOnly.ps1') -Raw -Encoding UTF8
        $source | Should -Match "Mode='DestinationReview'"
        $source | Should -Match 'Assert-OPA265BW4k2Claim'
        $source | Should -Match 'Assert-OPA265BW4k2StableAudits'
        $source | Should -Not -Match '(?i)\$mail\.(Move|Save|Delete|Send)\('
        $source | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
        $source | Should -Match 'DeltaSizeAccepted=\$false'
        $source | Should -Match 'ProductionReady=\$false'
    }
}
