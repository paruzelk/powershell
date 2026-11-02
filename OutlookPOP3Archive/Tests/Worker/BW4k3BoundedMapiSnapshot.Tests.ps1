#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k3BoundedMapiSnapshot265.ps1')
    function New-BW4k3FakeMail {
        $pa=New-Object PSObject
        $pa|Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
            param([string]$tag)
            if($tag -like '*0x0E080003'){return 6880}
            if($tag -like '*0x0E1B000B'){return $false}
            if($tag -like '*0x1035001F'){return '<test@example.net>'}
            throw 'Optional MAPI proptag unavailable in fake PST'
        }
        [pscustomobject]@{
            Class=43;EntryID='SOURCE-ENTRY'
            Parent=[pscustomobject]@{EntryID='SOURCE-FOLDER';StoreID='STORE-1'}
            PropertyAccessor=$pa
        }
    }
    function New-BW4k3SnapshotRecord {
        param([string]$SuiteId,[string]$TestId)
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k3.ImmutableSourceMapiEvidence.1'
            SuiteId=$SuiteId;TestId=$TestId
            PlanSha256=('a'*64)
            OriginalEvidenceSha256=('b'*64)
            FiveEvidenceSetSha256=('c'*64)
            OutlookMoveExecuted=$false
            ProductionReady=$false
        }
    }
}
Describe 'BW4k3 bounded read-only UnicodePlain MAPI hash snapshots and immutable capture' {
    BeforeEach {
        $script:suite=[guid]::NewGuid().ToString('D')
        $script:testId=[guid]::NewGuid().ToString('D')
        $script:fake=New-BW4k3FakeMail
        $script:opts=@{
            Mail=$script:fake;SuiteId=$script:suite;TestId=$script:testId
            ExpectedEntryId='SOURCE-ENTRY'
            ExpectedFolderEntryId='SOURCE-FOLDER'
            ExpectedStoreId='STORE-1'
        }
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }
    It 'has exactly fifteen fixed bounded MAPI property tags' {
        $specs=@(Get-OPA265BW4k3PropertySpecs)
        $specs.Count | Should -Be 15
        @($specs|Select-Object -ExpandProperty Tag|Select-Object -Unique).Count | Should -Be 15
        @($specs|Where-Object {$_.Tag -notmatch '^0x[A-F0-9]{8}$'}).Count | Should -Be 0
    }
    It 'hashes UTF8 Unicode text without revealing original text' {
        $x=ConvertTo-OPA265BW4k3HashedValue -Value 'Письмо'
        $x.Kind | Should -BeExactly 'UnicodeText'
        $x.ByteCount | Should -Be 12
        $x.Scalar | Should -BeExactly ''
        $x.Sha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'hashes binary bytes exactly' {
        $x=ConvertTo-OPA265BW4k3HashedValue -Value ([byte[]]@(0,1,255))
        $x.Kind | Should -BeExactly 'Binary'
        $x.ByteCount | Should -Be 3
        $x.Sha256 | Should -BeExactly (Get-OPA265BW4jSha256 -Bytes ([byte[]]@(0,1,255)))
    }
    It 'normalizes boolean scalar without text field leakage' {
        $x=ConvertTo-OPA265BW4k3HashedValue -Value $false
        $x.Kind | Should -BeExactly 'Boolean'
        $x.Scalar | Should -BeExactly 'False'
    }
    It 'normalizes signed integer in invariant form' {
        $x=ConvertTo-OPA265BW4k3HashedValue -Value ([int]6880)
        $x.Kind | Should -BeExactly 'SignedInteger'
        $x.Scalar | Should -BeExactly '6880'
    }
    It 'normalizes datetime to UTC ticks' {
        $x=ConvertTo-OPA265BW4k3HashedValue -Value ([datetime]'2025-01-01T00:00:00Z')
        $x.Kind | Should -BeExactly 'DateTimeUtcTicks'
        $x.Scalar | Should -Match '^[0-9]{18}$'
    }
    It 'fails closed for unsupported arbitrary objects' {
        {ConvertTo-OPA265BW4k3HashedValue -Value ([pscustomobject]@{Secret='x'})} | Should -Throw '*unsupported MAPI value*'
    }
    It 'fails closed for MAPI data exceeding size cap' {
        {ConvertTo-OPA265BW4k3HashedValue -Value ('x'*1025) -MaxBytes 1024} | Should -Throw '*bounded property*'
    }
    It 'reads exactly three available fake values and marks optional failures unavailable' {
        $s=Get-OPA265BW4k3MapiSnapshot @opts
        $s.PropertyCount | Should -Be 15
        $s.AvailableCount | Should -Be 3
        $s.Rows[0].Scalar | Should -Be '6880'
        @($s.Rows|Where-Object {$_.Kind -eq 'UnavailableOrError'}).Count | Should -Be 12
        $s.ProductionReady | Should -BeFalse
    }
    It 'two unchanged read-only MAPI snapshots compare exactly' {
        $a=Get-OPA265BW4k3MapiSnapshot @opts
        $b=Get-OPA265BW4k3MapiSnapshot @opts
        (Assert-OPA265BW4k3StableSnapshots -First $a -Second $b) | Should -BeTrue
    }
    It 'rejects altered subject-independent property bytes' {
        $a=Get-OPA265BW4k3MapiSnapshot @opts
        $b=Get-OPA265BW4k3MapiSnapshot @opts
        $b.Rows[0].Scalar='6881'
        {Assert-OPA265BW4k3StableSnapshots -First $a -Second $b} | Should -Throw '*snapshots disagree*'
    }
    It 'rejects invalid property tag ordering' {
        $a=Get-OPA265BW4k3MapiSnapshot @opts
        $b=Get-OPA265BW4k3MapiSnapshot @opts
        $b.Rows[0].Tag='0xFFFFFFFF'
        {Assert-OPA265BW4k3StableSnapshots -First $a -Second $b} | Should -Throw '*property spec order*'
    }
    It 'rejects wrong Outlook folder identity' {
        $opts.ExpectedFolderEntryId='OTHER-FOLDER'
        {Get-OPA265BW4k3MapiSnapshot @opts} | Should -Throw '*MailItem/Folder/Store ID changed*'
    }
    It 'creates separate immutable BOM JSON only once with SHA256 evidence' {
        $s=New-BW4k3SnapshotRecord -SuiteId $script:suite -TestId $script:testId
        $p=Get-OPA265BW4k3SnapshotPath -SuiteId $script:suite -TestId $script:testId -LocalAppData $script:root
        $one=Write-OPA265BW4k3SnapshotOnce -Snapshot $s -Path $p -LocalAppData $script:root
        $one.EvidenceSha256 | Should -Match '^[a-f0-9]{64}$'
        ([IO.File]::ReadAllBytes($p))[0] | Should -Be 239
        {Write-OPA265BW4k3SnapshotOnce -Snapshot $s -Path $p -LocalAppData $script:root} | Should -Throw
    }
    It 'blocks redirecting immutable evidence to another location' {
        $s=New-BW4k3SnapshotRecord -SuiteId $script:suite -TestId $script:testId
        {Write-OPA265BW4k3SnapshotOnce -Snapshot $s -Path (Join-Path $script:root 'wrong.json') -LocalAppData $script:root} | Should -Throw '*cannot be redirected*'
    }
    It 'blocks false production or claimed Move on source snapshot' {
        $s=New-BW4k3SnapshotRecord -SuiteId $script:suite -TestId $script:testId
        $s.OutlookMoveExecuted=$true
        $p=Get-OPA265BW4k3SnapshotPath -SuiteId $script:suite -TestId $script:testId -LocalAppData $script:root
        {Write-OPA265BW4k3SnapshotOnce -Snapshot $s -Path $p -LocalAppData $script:root} | Should -Throw '*unsafe immutable*'
    }
    It 'script is UnicodePlain-only, pre-Move and never has Outlook writer calls' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k3UnicodePreMoveMapi.ps1') -Raw -Encoding UTF8
        $src | Should -Match "'UnicodePlain'"
        $src | Should -Match 'Get-OPA265BW4k1EvidenceSet'
        $src | Should -Match 'Assert-OPA265BW4k1PinnedSource'
        $src | Should -Match 'Assert-OPA265BW4k3StableSnapshots'
        $src | Should -Match "Mode -ceq 'Capture'"
        $src | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\('
        $src | Should -Match 'ProductionReady=\$false'
    }
}
