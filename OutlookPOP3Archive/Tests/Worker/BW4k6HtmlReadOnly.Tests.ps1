#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k5HtmlEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k4UnicodeReadOnlyGuards265.ps1')
    function New-BW4k6Synthetic {
        $sid='74912f94-d523-4856-9efd-d5528a92426f'
        $tid='42db9da2-0596-4e17-aad7-52eeab0e4601'
        $orig=[pscustomobject]@{EntryId='SRC';FolderEntryId='SRC-FOLDER';StoreId='SRC-STORE';Size=8599}
        $rows=New-Object 'System.Collections.Generic.List[object]'
        foreach($spec in @(Get-OPA265BW4k3PropertySpecs)){
            $v=ConvertTo-OPA265BW4k3HashedValue -Value $spec.Name
            $rows.Add([pscustomobject][ordered]@{
                Name=$spec.Name;Tag=$spec.Tag;Kind=$v.Kind;Available=$true
                ByteCount=$v.ByteCount;Sha256=$v.Sha256;Scalar=$v.Scalar
            })
        }
        $snap=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k3.BoundedReadOnlyMapiPropertySnapshot.1'
            SuiteId=$sid;TestId=$tid;EntryId='SRC';FolderEntryId='SRC-FOLDER'
            StoreIdSha256=(Get-OPA265BW4jTextHash -Value 'SRC-STORE')
            Rows=@($rows.ToArray());PropertyCount=15;AvailableCount=15
            OutlookMoveExecuted=$false;ProductionReady=$false
        }
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k5.ImmutableHtmlBodySourceMapiEvidence.1'
            SuiteId=$sid;TestId=$tid;CaseName='HtmlBody'
            PlanSha256=('a'*64);OriginalEvidenceSha256=('b'*64)
            FiveEvidenceSetSha256=('c'*64)
            SourceEntryId='SRC';SourceFolderEntryId='SRC-FOLDER'
            SourceStoreIdSha256=$snap.StoreIdSha256
            SourceSize=8599;CapturedUtc=[datetime]::UtcNow.ToString('o')
            Snapshot=$snap;OutlookMoveExecuted=$false;ProductionReady=$false
        }
        [pscustomobject]@{
            Original=$orig;Record=$record;Snapshot=$snap
            Pins=@{Original=$orig;SuiteId=$sid;TestId=$tid;ExpectedPlanSha256=('a'*64);ExpectedFiveEvidenceSetSha256=('c'*64);OriginalEvidenceSha256=('b'*64)}
        }
    }
    function Copy-BW4k6Target {
        param([object]$Source)
        $copy=$Source|ConvertTo-Json -Depth 9|ConvertFrom-Json
        $copy.EntryId='DEST';$copy.FolderEntryId='DEST-FOLDER'
        $copy.StoreIdSha256=(Get-OPA265BW4jTextHash -Value 'DEST-STORE')
        return $copy
    }
}
Describe 'BW4k6 exact HtmlBody immutable pre/post MAPI audit and static no-writer enforcement' {
    BeforeEach {
        $script:fixture=New-BW4k6Synthetic
        $script:pins=$script:fixture.Pins
    }
    It 'validates the unchanged HtmlBody evidence structure' {
        (Assert-OPA265BW4k5HtmlRecord -Record $script:fixture.Record @pins) | Should -BeTrue
    }
    It 'rejects another HtmlBody original source ID' {
        $script:fixture.Record.SourceEntryId='FOREIGN'
        {Assert-OPA265BW4k5HtmlRecord -Record $script:fixture.Record @pins} | Should -Throw '*SourceEntryId*'
    }
    It 'reports exactly 15 matched MAPI digests across distinct PST' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $r=Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest
        $r.PropertyCount | Should -Be 15
        $r.MatchedCount | Should -Be 15
        $r.ChangedCount | Should -Be 0
        $r.MAPI38ByteCauseProven | Should -BeFalse
    }
    It 'reports HTML digest difference without automatically accepting' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $dest.Rows[14].Sha256='f'*64
        $r=Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest
        $r.PropertyRows[14].Name | Should -Be 'PR_HTML'
        $r.PropertyRows[14].Status | Should -Be 'Changed'
        $r.DeltaSizeAccepted | Should -BeFalse
    }
    It 'detects MAPI size drift without proving cause' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $dest.Rows[0].Sha256='f'*64
        $dest.Rows[0].Scalar='8637'
        $r=Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest
        $r.ChangedCount | Should -Be 1
        $r.MAPI38ByteCauseProven | Should -BeFalse
    }
    It 'separately classifies optional MAPI property becoming unavailable' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $dest.Rows[14].Kind='UnavailableOrError'
        $dest.Rows[14].Available=$false
        $dest.Rows[14].Sha256=''
        $dest.Rows[14].Scalar=''
        $r=Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest
        $r.AvailabilityChangedCount | Should -Be 1
        $r.ChangedCount | Should -Be 0
    }
    It 'blocks same-PST identity erroneously classified as a cross-PST move' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $dest.StoreIdSha256=$script:fixture.Snapshot.StoreIdSha256
        {Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest} | Should -Throw '*not distinct*'
    }
    It 'blocks different MailItem TestId in comparison' {
        $dest=Copy-BW4k6Target -Source $script:fixture.Snapshot
        $dest.TestId='not-this-test'
        {Compare-OPA265BW4k4MapiSnapshots -Original $script:fixture.Snapshot -Destination $dest} | Should -Throw '*not distinct*'
    }
    It 'script pins exact SHA256 of BW4k5 original HtmlBody capture' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match '755242f7ea0c270e12236f20a2b578a9b43dc648b105ae6c5c0ccce5caada3be'
        $src | Should -Match '1689ee2b6b8aead84eed5dcf5884a61603f0b7f335f48601ebafb19dbb2c3eec'
    }
    It 'script checks both old immutable Move claims in both modes' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        @([regex]::Matches($src,'Assert-OPA265BW4k5HistoricCompletedMoves')).Count | Should -BeGreaterOrEqual 3
    }
    It 'script enforces original live 15-property source MAPI equality pre-Move' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'Assert-OPA265BW4k3StableSnapshots -First \$pre.Snapshot -Second \$live2'
        $src | Should -Match "Status='OriginalHtmlMapiAndEmptyTargetReviewedNoMove'"
    }
    It 'script requires exact empty target using independent BW4k1 Review' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match "Invoke-OPA265BW4k1RealOneShotMove.ps1"
        $src | Should -Match "'ExactOneShotRealDisposableReviewPassedNoMove'"
        $src | Should -Match 'PriorClaimExists=\$false'
    }
    It 'post-Move comparison must check exact immutable BW4k1 Claim and content twice' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'Assert-OPA265BW4k2Claim'
        $src | Should -Match 'Assert-OPA265BW4k2StableAudits'
        $src | Should -Match 'Compare-OPA265BW4k4MapiSnapshots'
    }
    It 'production and size waiver remain disabled for HtmlBody' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'DeltaSizeAccepted=\$false'
        $src | Should -Match 'PhysicalPstDurabilityProven=\$false'
        $src | Should -Match 'ProductionReady=\$false'
    }
    It 'script never invokes MailItem Move Save Send Delete or claim mutation' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\('
        $src | Should -Not -Match '(?i)\$srcMail\.(Move|Save|Send|Delete)\('
        $src | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
        $src | Should -Not -Match '\bAddStoreEx\('
    }
    It 'source witness remains case-specific with nonempty HTMLBody and no attachments' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k6HtmlReadOnly.ps1') -Raw -Encoding UTF8
        $src | Should -Match '\$original.HtmlBodyLength -lt 1'
        $src | Should -Match '\$original.Attachments'
        $src | Should -Match "'HtmlBody'"
    }
}
