#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k1RealOneShotGuards265.ps1')
    function Get-BW4k1FakeWitness {
        param([object]$Case,[string]$SuiteId)
        $attachments=@()
        if([int]$Case.ExpectedAttachmentCount -eq 1){
            $attachments=@([pscustomobject][ordered]@{
                Index=1;FileName='test.bin'
                ByteCount=[long]$Case.MinimumAttachmentBytes
                Sha256=('a'*64)
            })
        }
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
            SuiteId=$SuiteId
            CaseName=[string]$Case.Name
            TestId=[string]$Case.TestId
            ProfileName='Outlook'
            EntryId='SourceEntryId'
            FolderEntryId='InboxId'
            StoreId='POP3StoreId'
            InternetMessageId='<test@example.com>'
            SearchKeySha256=('a'*64)
            SubjectUtf8Sha256=('a'*64)
            SenderUtf8Sha256=('b'*64)
            BodyUtf8Sha256=('c'*64)
            HtmlBodyUtf8Sha256=('d'*64)
            SubjectLength=50
            BodyLength=100
            HtmlBodyLength=150
            Size=6000
            ReceivedUtcTicks=638500000000000000
            Attachments=$attachments
            OutlookMoveExecuted=$false
            ProductionReady=$false
        }
    }
    function New-BW4k1TestSet {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param([string]$LocalAppData)
        $p=New-OPA265BW4jPlan
        foreach($c in @($p.Cases)){
            $w=Get-BW4k1FakeWitness -Case $c -SuiteId $p.SuiteId
            $path=Get-OPA265BW4jEvidencePath -SuiteId $p.SuiteId -TestId $c.TestId -LocalAppData $LocalAppData
            if($PSCmdlet.ShouldProcess($path,'Create disposable fake source witness')){
                [void](Write-OPA265BW4jOnce -Object $w -Path $path)
            }
        }
        return $p
    }
}
Describe 'BW4k1 real one-shot source scope, immutable evidence set and irreversible claims' {
    BeforeEach {
        $script:p=New-OPA265BW4jPlan
        $script:c=$script:p.Cases[0]
        $script:w=Get-BW4k1FakeWitness -Case $script:c -SuiteId $script:p.SuiteId
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }
    It 'uses canonical TestId and independent suite-scoped irreversible claim path' {
        $path=Get-OPA265BW4k1ClaimPath -SuiteId $script:p.SuiteId -TestId $script:c.TestId -LocalAppData $script:root
        $path | Should -Match 'OutlookPOP3Archive-BW4k1-Claims'
        $path | Should -Match ([regex]::Escape($script:p.SuiteId))
        $path | Should -Match ([regex]::Escape($script:c.TestId))
    }
    It 'rejects malformed or previously used noncanonical TestId' {
        {Get-OPA265BW4k1ClaimPath -SuiteId $script:p.SuiteId -TestId 'bad' -LocalAppData $script:root} | Should -Throw '*canonical TestId*'
    }
    It 'allows exact previously sealed source fields only' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        (Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId) | Should -BeTrue
    }
    It 'blocks a changed source subject hash' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.SubjectUtf8Sha256='f'*64
        {Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId} | Should -Throw '*SubjectUtf8Sha256*'
    }
    It 'blocks source MAPI Size drift without blanket acceptance' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.Size=6038
        {Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId} | Should -Throw '*Size*'
    }
    It 'blocks source InternetMessageId drift' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.InternetMessageId='<different@example.com>'
        {Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId} | Should -Throw '*InternetMessageId*'
    }
    It 'blocks source StoreId drift to a different mailbox' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.StoreId='WrongStore'
        {Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId} | Should -Throw '*StoreId*'
    }
    It 'blocks source HTML body drift' {
        $clone=($script:w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.HtmlBodyUtf8Sha256='e'*64
        {Assert-OPA265BW4k1PinnedSource -Original $script:w -Current $clone -Case $script:c -SuiteId $script:p.SuiteId} | Should -Throw '*HtmlBodyUtf8Sha256*'
    }
    It 'blocks binary attachment SHA drift' {
        $c=$script:p.Cases[3]
        $w=Get-BW4k1FakeWitness -Case $c -SuiteId $script:p.SuiteId
        $clone=($w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.Attachments[0].Sha256='e'*64
        {Assert-OPA265BW4k1PinnedSource -Original $w -Current $clone -Case $c -SuiteId $script:p.SuiteId} | Should -Throw '*binary attachment drift*'
    }
    It 'blocks binary attachment size drift' {
        $c=$script:p.Cases[4]
        $w=Get-BW4k1FakeWitness -Case $c -SuiteId $script:p.SuiteId
        $clone=($w|ConvertTo-Json -Depth 9|ConvertFrom-Json)
        $clone.Attachments[0].ByteCount++
        {Assert-OPA265BW4k1PinnedSource -Original $w -Current $clone -Case $c -SuiteId $script:p.SuiteId} | Should -Throw '*binary attachment drift*'
    }
    It 'seals exactly five original witnesses in deterministic plan order' {
        $p=New-BW4k1TestSet -LocalAppData $script:root
        $a=Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId $p.SuiteId -LocalAppData $script:root
        $b=Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId $p.SuiteId -LocalAppData $script:root
        $a.Count | Should -Be 5
        $a.EvidenceSetSha256 | Should -Match '^[a-f0-9]{64}$'
        $a.EvidenceSetSha256 | Should -BeExactly $b.EvidenceSetSha256
        @($a.OriginalEvidenceSha256Lines).Count | Should -Be 5
        $a.ProductionReady | Should -BeFalse
    }
    It 'stops when any of the five original evidence files is missing' {
        $p=New-BW4k1TestSet -LocalAppData $script:root
        $path=Get-OPA265BW4jEvidencePath -SuiteId $p.SuiteId -TestId $p.Cases[4].TestId -LocalAppData $script:root
        Remove-Item -LiteralPath $path -Force
        {Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId $p.SuiteId -LocalAppData $script:root} | Should -Throw '*absent/unsafe*'
    }
    It 'a changed but valid original witness produces a different five-evidence seal' {
        $p=New-BW4k1TestSet -LocalAppData $script:root
        $a=Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId $p.SuiteId -LocalAppData $script:root
        $path=Get-OPA265BW4jEvidencePath -SuiteId $p.SuiteId -TestId $p.Cases[2].TestId -LocalAppData $script:root
        $w=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        $w.BodyLength++
        $encoding=New-Object Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $w -Depth 9),$encoding)
        $b=Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId $p.SuiteId -LocalAppData $script:root
        $a.EvidenceSetSha256 | Should -Not -BeExactly $b.EvidenceSetSha256
    }
    It 'rejects a five-evidence set pinned to a different SuiteId' {
        $p=New-BW4k1TestSet -LocalAppData $script:root
        {Get-OPA265BW4k1EvidenceSet -Plan $p -SuiteId ([guid]::NewGuid().ToString('D')) -LocalAppData $script:root} | Should -Throw '*SuiteId mismatch*'
    }
    It 'writes one durable immutable BOM claim and refuses replay' {
        $path=Get-OPA265BW4k1ClaimPath -SuiteId $script:p.SuiteId -TestId $script:c.TestId -LocalAppData $script:root
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
            SuiteId=$script:p.SuiteId;TestId=$script:c.TestId
            SourceEvidenceSha256=('a'*64);EvidenceSetSha256=('b'*64);PlanSha256=('c'*64)
            RealOutlookOneShot=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $r=Write-OPA265BW4k1ClaimOnce -Claim $claim -ClaimPath $path -LocalAppData $script:root
        $r.ClaimSha256 | Should -Match '^[a-f0-9]{64}$'
        ([IO.File]::ReadAllBytes($path))[0] | Should -Be 239
        {Write-OPA265BW4k1ClaimOnce -Claim $claim -ClaimPath $path -LocalAppData $script:root} | Should -Throw
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $r.ClaimSha256
    }
    It 'refuses to redirect an irreversible claim to arbitrary path' {
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
            SuiteId=$script:p.SuiteId;TestId=$script:c.TestId
            SourceEvidenceSha256=('a'*64);EvidenceSetSha256=('b'*64);PlanSha256=('c'*64)
            RealOutlookOneShot=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        {Write-OPA265BW4k1ClaimOnce -Claim $claim -ClaimPath (Join-Path $script:root 'wrong.json') -LocalAppData $script:root} | Should -Throw '*cannot be redirected*'
    }
    It 'refuses a claim permitting automatic retry' {
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
            SuiteId=$script:p.SuiteId;TestId=$script:c.TestId
            SourceEvidenceSha256=('a'*64);EvidenceSetSha256=('b'*64);PlanSha256=('c'*64)
            RealOutlookOneShot=$true;AutomaticRetryAllowed=$true;ProductionReady=$false
        }
        $path=Get-OPA265BW4k1ClaimPath -SuiteId $script:p.SuiteId -TestId $script:c.TestId -LocalAppData $script:root
        {Write-OPA265BW4k1ClaimOnce -Claim $claim -ClaimPath $path -LocalAppData $script:root} | Should -Throw '*unsafe irreversible claim*'
    }
    It 'BW4k1a WhatIf of Seal runs complete file preflight then refuses dry-run Seal explicitly' {
        $oldLocal=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=$script:root
            $p=New-BW4k1TestSet -LocalAppData $script:root
            $planPath=Get-OPA265BW4jPlanPath -SuiteId $p.SuiteId -LocalAppData $script:root
            [void](Write-OPA265BW4jOnce -Object $p -Path $planPath)
            $sha=(Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $runner=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
            { & $runner -Mode Seal -SuiteId $p.SuiteId -ExpectedPlanSha256 $sha -WhatIf } |
                Should -Throw '*Seal accepts only exact SuiteId and plan SHA*'
        } finally {
            $env:LOCALAPPDATA=$oldLocal
        }
    }
    It 'BW4k1a normal Seal still returns exactly five evidence hashes without COM' {
        $oldLocal=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=$script:root
            $p=New-BW4k1TestSet -LocalAppData $script:root
            $planPath=Get-OPA265BW4jPlanPath -SuiteId $p.SuiteId -LocalAppData $script:root
            [void](Write-OPA265BW4jOnce -Object $p -Path $planPath)
            $sha=(Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $runner=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
            $result=& $runner -Mode Seal -SuiteId $p.SuiteId -ExpectedPlanSha256 $sha
            $result.Count | Should -Be 5
            $result.EvidenceSetSha256 | Should -Match '^[a-f0-9]{64}
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        ([regex]::Matches($source,'(?i)\$mail\.Move\(\$destFolder\)')).Count | Should -Be 1
        $source | Should -Not -Match '(?i)\$mail\.(Send|Save|Delete)\('
        $source | Should -Match 'Write-OPA265BW4k1ClaimOnce'
        $source.IndexOf('Write-OPA265BW4k1ClaimOnce') | Should -BeLessThan $source.IndexOf('$mail.Move($destFolder)')
        $source | Should -Match 'SupportsShouldProcess'
    }
}

        } finally {
            $env:LOCALAPPDATA=$oldLocal
        }
    }
    It 'BW4k1a explicit dry-run guard precedes irreversible claim creation' {
        $runner=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
        $source=Get-Content -LiteralPath $runner -Raw -Encoding UTF8
        $capture=$source.IndexOf('$requestedWhatIf=[bool]$WhatIfPreference')
        $disable=$source.IndexOf('if($requestedWhatIf){$WhatIfPreference=$false}')
        $preflight=$source.IndexOf('$planPath=Get-OPA265BW4jPlanPath')
        $guard=$source.IndexOf('if($requestedWhatIf){', $preflight)
        $claim=$source.IndexOf('$written=Write-OPA265BW4k1ClaimOnce')
        $move=$source.IndexOf('$moved=$mail.Move($destFolder)')
        $capture | Should -BeGreaterThan -1
        $disable | Should -BeGreaterThan $capture
        $preflight | Should -BeGreaterThan $disable
        $guard | Should -BeGreaterThan $preflight
        $claim | Should -BeGreaterThan $guard
        $move | Should -BeGreaterThan $claim
    }
    It 'one-shot script never uses Send/Save/Remove and contains one explicit Move call' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        ([regex]::Matches($source,'(?i)\$mail\.Move\(\$destFolder\)')).Count | Should -Be 1
        $source | Should -Not -Match '(?i)\$mail\.(Send|Save|Delete)\('
        $source | Should -Match 'Write-OPA265BW4k1ClaimOnce'
        $source.IndexOf('Write-OPA265BW4k1ClaimOnce') | Should -BeLessThan $source.IndexOf('$mail.Move($destFolder)')
        $source | Should -Match 'SupportsShouldProcess'
    }
}
