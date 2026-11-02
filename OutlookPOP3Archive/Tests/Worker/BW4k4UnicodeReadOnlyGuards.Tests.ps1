#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k4UnicodeReadOnlyGuards265.ps1')
    function New-BW4k4SyntheticSet {
        $sid=[guid]::NewGuid().ToString('D')
        $tid=[guid]::NewGuid().ToString('D')
        $original=[pscustomobject]@{
            CaseName='UnicodePlain';EntryId='SOURCE-ENTRY'
            FolderEntryId='SOURCE-FOLDER';StoreId='SOURCE-STORE'
            Size=6880
        }
        $rows=New-Object 'System.Collections.Generic.List[object]'
        foreach($spec in @(Get-OPA265BW4k3PropertySpecs)){
            $val=ConvertTo-OPA265BW4k3HashedValue -Value ([string]$spec.Name)
            $rows.Add([pscustomobject][ordered]@{
                Name=$spec.Name;Tag=$spec.Tag
                Kind=$val.Kind;Available=$true
                ByteCount=$val.ByteCount;Sha256=$val.Sha256
                Scalar=$val.Scalar
            })
        }
        $snapshot=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k3.BoundedReadOnlyMapiPropertySnapshot.1'
            SuiteId=$sid;TestId=$tid
            EntryId='SOURCE-ENTRY';FolderEntryId='SOURCE-FOLDER'
            StoreIdSha256=(Get-OPA265BW4jTextHash -Value 'SOURCE-STORE')
            Rows=@($rows.ToArray())
            PropertyCount=15;AvailableCount=15
            OutlookMoveExecuted=$false
            ProductionReady=$false
        }
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k3.ImmutableSourceMapiEvidence.1'
            SuiteId=$sid;TestId=$tid;CaseName='UnicodePlain'
            PlanSha256=('a'*64)
            OriginalEvidenceSha256=('b'*64)
            FiveEvidenceSetSha256=('c'*64)
            SourceEntryId='SOURCE-ENTRY'
            SourceFolderEntryId='SOURCE-FOLDER'
            SourceStoreIdSha256=$snapshot.StoreIdSha256
            SourceSize=6880
            CapturedUtc=[datetime]::UtcNow.ToString('o')
            Snapshot=$snapshot
            OutlookMoveExecuted=$false
            ProductionReady=$false
        }
        [pscustomobject]@{
            Record=$record;Original=$original;SuiteId=$sid;TestId=$tid
            Inputs=@{
                Original=$original;SuiteId=$sid;TestId=$tid
                PlanSha256=('a'*64);FiveEvidenceSetSha256=('c'*64)
                SourceEvidenceSha256=('b'*64)
            }
        }
    }
    function New-BW4k4Target {
        param([object]$Source)
        $d=$Source|ConvertTo-Json -Depth 9|ConvertFrom-Json
        $d.EntryId='TARGET-ENTRY'
        $d.FolderEntryId='TARGET-FOLDER'
        $d.StoreIdSha256=(Get-OPA265BW4jTextHash -Value 'TARGET-STORE')
        return $d
    }
}
Describe 'BW4k4 original Unicode MAPI source seal and no-writer cross-PST digest comparison' {
    BeforeEach {
        $script:sample=New-BW4k4SyntheticSet
        $script:pins=$script:sample.Inputs
    }
    It 'accepts exact original bounded source metadata with all pins' {
        (Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins) | Should -BeTrue
    }
    It 'blocks an unpinned other SuiteId' {
        $script:sample.Record.SuiteId=[guid]::NewGuid().ToString('D')
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*SuiteId*'
    }
    It 'blocks wrong source SHA256 pin' {
        $script:sample.Record.OriginalEvidenceSha256='f'*64
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*OriginalEvidenceSha256*'
    }
    It 'blocks wrong exact source size' {
        $script:sample.Record.SourceSize=6881
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*SourceSize*'
    }
    It 'blocks foreign source StoreId SHA256' {
        $script:sample.Record.SourceStoreIdSha256='0'*64
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*SourceStoreIdSha256*'
    }
    It 'blocks extra property suggesting move permission' {
        $script:sample.Record|Add-Member -NotePropertyName CanMove -NotePropertyValue $true
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*cardinality*'
    }
    It 'blocks false Move flag in original evidence' {
        $script:sample.Record.OutlookMoveExecuted=$true
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*wrongly claims move*'
    }
    It 'blocks malformed embedded source identity' {
        $script:sample.Record.Snapshot.EntryId='OTHER'
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*embedded source identity*'
    }
    It 'blocks malformed or reordered MAPI property specification' {
        $script:sample.Record.Snapshot.Rows[2].Tag='0xFFFFFFFF'
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*spec order*'
    }
    It 'blocks fabricated MAPI property availability count' {
        $script:sample.Record.Snapshot.AvailableCount=14
        {Assert-OPA265BW4k4OriginalMapiEvidence -Record $script:sample.Record @pins} | Should -Throw '*availability count*'
    }
    It 'reports 15 matched properties without declaring byte identity' {
        $a=$script:sample.Record.Snapshot
        $b=New-BW4k4Target -Source $a
        $result=Compare-OPA265BW4k4MapiSnapshots -Original $a -Destination $b
        $result.PropertyCount | Should -Be 15
        $result.MatchedCount | Should -Be 15
        $result.ChangedCount | Should -Be 0
        $result.FullMAPIByteEqualityProven | Should -BeFalse
        $result.MAPI38ByteCauseProven | Should -BeFalse
    }
    It 'reports MAPI value drift with both original and destination SHA256' {
        $a=$script:sample.Record.Snapshot
        $b=New-BW4k4Target -Source $a
        $b.Rows[0].Sha256='f'*64
        $result=Compare-OPA265BW4k4MapiSnapshots -Original $a -Destination $b
        $result.ChangedCount | Should -Be 1
        $result.PropertyRows[0].Status | Should -BeExactly 'Changed'
        $result.PropertyRows[0].SourceSha256 | Should -Not -BeExactly $result.PropertyRows[0].DestinationSha256
    }
    It 'reports unavailable destination property separately from altered data' {
        $a=$script:sample.Record.Snapshot
        $b=New-BW4k4Target -Source $a
        $b.Rows[5].Available=$false
        $b.Rows[5].Kind='UnavailableOrError'
        $b.Rows[5].Sha256=''
        $b.Rows[5].Scalar=''
        $result=Compare-OPA265BW4k4MapiSnapshots -Original $a -Destination $b
        $result.AvailabilityChangedCount | Should -Be 1
        $result.ChangedCount | Should -Be 0
    }
    It 'rejects comparing same-store item as cross-PST Move' {
        $a=$script:sample.Record.Snapshot
        $b=New-BW4k4Target -Source $a
        $b.StoreIdSha256=$a.StoreIdSha256
        {Compare-OPA265BW4k4MapiSnapshots -Original $a -Destination $b} | Should -Throw '*not distinct*'
    }
    It 'rejects another TestId in destination evidence' {
        $a=$script:sample.Record.Snapshot
        $b=New-BW4k4Target -Source $a
        $b.TestId=[guid]::NewGuid().ToString('D')
        {Compare-OPA265BW4k4MapiSnapshots -Original $a -Destination $b} | Should -Throw '*not distinct*'
    }
    It 'refuses post-Move conclusions and writer calls in top-level script' {
        $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k4UnicodeReadOnly.ps1') -Raw -Encoding UTF8
        $source | Should -Match "ValidateSet\('PreMoveReview','PostMoveCompare'\)"
        $source | Should -Match 'ExpectedSourceMapiSnapshotSha256'
        $source | Should -Match 'Assert-OPA265BW4k2Claim'
        $source | Should -Match 'Assert-OPA265BW4k3StableSnapshots'
        $source | Should -Match 'Get-OPA265BW4k3MapiSnapshot'
        $source | Should -Match 'DeltaSizeAccepted=\$false'
        $source | Should -Match 'ProductionReady=\$false'
        $source | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\('
        $source | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
    }
}
