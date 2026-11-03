#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7dRecipientFlagWitness265.ps1')
    function New-BW4k7dFixture {
        [pscustomobject]@{
            Recipients=@(
                [pscustomobject][ordered]@{Index=1;Type=1;Name='Test To';Address='recipient@example.test'},
                [pscustomobject][ordered]@{Index=2;Type=2;Name='Test CC';Address='copy@example.test'}
            )
            State=[pscustomobject][ordered]@{
                UnRead=$false;Categories='Project';Importance=1
                Sensitivity=0;FlagStatus=0;FlagRequest=''
                ReminderSet=$false
                To='Test To';CC='Test CC';BCC=''
            }
        }
    }
}
Describe 'BW4k7d SEM-001 original recipient/state coverage read-only witness' {
    BeforeEach {
        $script:f=New-BW4k7dFixture
        $script:opts=@{
            Recipients=$script:f.Recipients;State=$script:f.State
            MapiFlags=65555;AttachmentCount=1
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
        }
    }
    It 'captures all recipient types and 2 SHA digests without exposing addresses' {
        $w=Get-OPA265BW4k7dWitness @opts
        $w.RecipientCount | Should -Be 2
        $w.ToCount | Should -Be 1
        $w.CcCount | Should -Be 1
        $w.BccCount | Should -Be 0
        $w.RecipientDigestSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.UserStateDigestSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.PSObject.Properties.Name | Should -Not -Contain 'Address'
    }
    It 'does not permit writes or claim production-grade coverage' {
        $w=Get-OPA265BW4k7dWitness @opts
        $w.WriterPermit | Should -BeFalse
        $w.ProductionReady | Should -BeFalse
        $w.PreMoveSemanticSnapshotPersisted | Should -BeFalse
        $w.ProductionSignificantFlagCoverageProven | Should -BeFalse
    }
    It 'identical repeat read must pass' {
        $a=Get-OPA265BW4k7dWitness @opts
        $b=Get-OPA265BW4k7dWitness @opts
        (Assert-OPA265BW4k7dStableWitness -First $a -Second $b) | Should -BeTrue
    }
    It 'different recipient address changes digest and blocks stability' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.Recipients[1].Address='different@example.test'
        $b=Get-OPA265BW4k7dWitness @opts
        {Assert-OPA265BW4k7dStableWitness -First $a -Second $b} | Should -Throw '*two live reads*'
    }
    It 'different recipient name changes digest' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.Recipients[0].Name='Different'
        $b=Get-OPA265BW4k7dWitness @opts
        $a.RecipientDigestSha256 | Should -Not -BeExactly $b.RecipientDigestSha256
    }
    It 'recipient order changes digest even with same addresses' {
        $a=Get-OPA265BW4k7dWitness @opts
        $first=$script:f.Recipients[0]
        $second=$script:f.Recipients[1]
        $script:f.Recipients=@(
            [pscustomobject][ordered]@{Index=1;Type=$second.Type;Name=$second.Name;Address=$second.Address},
            [pscustomobject][ordered]@{Index=2;Type=$first.Type;Name=$first.Name;Address=$first.Address}
        )
        $script:opts.Recipients=$script:f.Recipients
        $b=Get-OPA265BW4k7dWitness @opts
        $a.RecipientDigestSha256 | Should -Not -BeExactly $b.RecipientDigestSha256
    }
    It 'BCC recipient is counted and hashed distinctly' {
        $script:f.Recipients+=([pscustomobject][ordered]@{Index=3;Type=3;Name='Blind';Address='blind@example.test'})
        $script:opts.Recipients=$script:f.Recipients
        $w=Get-OPA265BW4k7dWitness @opts
        $w.BccCount | Should -Be 1
        $w.RecipientCount | Should -Be 3
    }
    It 'requires at least one addressable recipient' {
        $script:opts.Recipients=@()
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw # Locale-neutral PS5.1 binder failure
    }
    It 'rejects blank recipient Address' {
        $script:f.Recipients[0].Address=''
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*Address missing*'
    }
    It 'rejects recipient count above 256' {
        $script:opts.Recipients=@(1..257 | ForEach-Object {[pscustomobject]@{Index=$_;Type=1;Name='x';Address='a@example.test'}})
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*recipient count*'
    }
    It 'rejects invalid recipient type outside To/Cc/Bcc' {
        $script:f.Recipients[0].Type=4
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*order, type*'
    }
    It 'rejects duplicate Index' {
        $script:f.Recipients[1].Index=1
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*order, type*'
    }
    It 'rejects unexpected recipient fields' {
        $script:f.Recipients[0] | Add-Member -NotePropertyName AddressEntry -NotePropertyValue 'extra'
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*order, type*'
    }
    It 'rejects unsafe oversized address' {
        $script:f.Recipients[0].Address='x'*4097
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*Address missing*'
    }
    It 'detects changes in UnRead state in user-state digest' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.UnRead=$true
        $script:opts.MapiFlags=65554
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
        $b.UnRead | Should -BeTrue
    }
    It 'blocks MAPI READ flag and Outlook UnRead mismatch' {
        $script:opts.MapiFlags=65554
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*semantic mask*'
    }
    It 'blocks MAPI HASATTACH bit and attachment count mismatch' {
        $script:opts.MapiFlags=65539
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*semantic mask*'
    }
    It 'changed Categories changes stable state hash' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.Categories='Other'
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
    }
    It 'changed Importance changes stable state hash' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.Importance=2
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
    }
    It 'changed FlagStatus changes stable state hash' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.FlagStatus=1
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
    }
    It 'changed reminder state changes digest' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.ReminderSet=$true
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
    }
    It 'changed BCC text changes digest' {
        $a=Get-OPA265BW4k7dWitness @opts
        $script:f.State.BCC='hidden'
        $b=Get-OPA265BW4k7dWitness @opts
        $a.UserStateDigestSha256 | Should -Not -BeExactly $b.UserStateDigestSha256
    }
    It 'incomplete user-state schema fails closed' {
        $script:f.State.PSObject.Properties.Remove('FlagRequest')
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*complete user-state*'
    }
    It 'unexpected extra state field fails closed' {
        $script:f.State | Add-Member -NotePropertyName AllowWriter -NotePropertyValue $true
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*complete user-state*'
    }
    It 'non-boolean UnRead fails closed' {
        $script:f.State.UnRead='False'
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*boolean state*'
    }
    It 'invalid FlagStatus enum fails closed' {
        $script:f.State.FlagStatus=99
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*enum state*'
    }
    It 'cannot repurpose an unrelated fixture TestId' {
        $script:opts.TestId=[guid]::NewGuid().ToString('D')
        {Get-OPA265BW4k7dWitness @opts} | Should -Throw '*exact original*'
    }
    It 'refuses forged permission in stable snapshot' {
        $a=Get-OPA265BW4k7dWitness @opts
        $b=Get-OPA265BW4k7dWitness @opts
        $b.WriterPermit=$true
        {Assert-OPA265BW4k7dStableWitness -First $a -Second $b} | Should -Throw '*unauthorized elevation*'
    }
    It 'cannot present incomplete recipient rows as stable' {
        $a=Get-OPA265BW4k7dWitness @opts
        $b=Get-OPA265BW4k7dWitness @opts
        $b.CompleteRecipientEnumeration=$false
        {Assert-OPA265BW4k7dStableWitness -First $a -Second $b} | Should -Throw '*incomplete recipients*'
    }
    It 'requires previously verified exact decision SHA in standalone entrypoint' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7dRecipientFlagsReview.ps1'
        $text=Get-Content -LiteralPath $p -Encoding UTF8 -Raw
        $text | Should -Match '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6'
        $text | Should -Match 'Invoke-OPA265BW4k7cExactSourceSizeDecision.ps1'
        $text | Should -Not -Match '(?i)\$mail\.(Move|Save|Delete|Send)\s*\('
    }
    It 'has no local file creation, decision writer or MAPI setter' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7dRecipientFlagsReview.ps1'
        $text=Get-Content -LiteralPath $p -Encoding UTF8 -Raw
        $text | Should -Not -Match 'Write-OPA265BW4k7cManualDecisionOnce'
        $text | Should -Not -Match 'FileMode\]::CreateNew'
        $text | Should -Not -Match 'SetProperty\s*\('
    }
}
