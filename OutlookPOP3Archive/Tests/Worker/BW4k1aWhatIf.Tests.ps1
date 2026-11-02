#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k1RealOneShotGuards265.ps1')
    function Initialize-OPA265BW4k1aFakeSuite {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param([Parameter(Mandatory=$true)][string]$LocalAppData)
        $p=New-OPA265BW4jPlan
        $pp=Get-OPA265BW4jPlanPath -SuiteId $p.SuiteId -LocalAppData $LocalAppData
        if($PSCmdlet.ShouldProcess($pp,'Create isolated BW4k1a test-only plan')){
            [void](Write-OPA265BW4jOnce -Object $p -Path $pp)
        }
        foreach($c in @($p.Cases)){
            $att=@()
            if([int]$c.ExpectedAttachmentCount -eq 1){
                $att=@([pscustomobject][ordered]@{
                    Index=1;FileName='fixture.bin'
                    ByteCount=[long]$c.MinimumAttachmentBytes
                    Sha256=('a'*64)
                })
            }
            $w=[pscustomobject][ordered]@{
                Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
                SuiteId=$p.SuiteId;CaseName=$c.Name;TestId=$c.TestId
                ProfileName='Outlook';EntryId='fake-entry-id'
                FolderEntryId='fake-inbox';StoreId='fake-pop3-store'
                InternetMessageId='<fixture@example.com>'
                SearchKeySha256=('a'*64)
                SubjectUtf8Sha256=('a'*64);SenderUtf8Sha256=('b'*64)
                BodyUtf8Sha256=('c'*64);HtmlBodyUtf8Sha256=('d'*64)
                SubjectLength=30;BodyLength=50;HtmlBodyLength=80
                Size=6000;ReceivedUtcTicks=638500000000000000
                Attachments=$att
                OutlookMoveExecuted=$false;ProductionReady=$false
            }
            $path=Get-OPA265BW4jEvidencePath -SuiteId $p.SuiteId -TestId $c.TestId -LocalAppData $LocalAppData
            if($PSCmdlet.ShouldProcess($path,'Create isolated BW4k1a test-only evidence')){
                [void](Write-OPA265BW4jOnce -Object $w -Path $path)
            }
        }
        return [pscustomobject]@{
            SuiteId=$p.SuiteId
            PlanSha256=(Get-FileHash -LiteralPath $pp -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
Describe 'BW4k1a WhatIf path resolution regressions without Outlook/claims' {
    It 'Seal -WhatIf reads the full fake evidence and rejects Seal explicitly, not NULL path' {
        $old=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $set=Initialize-OPA265BW4k1aFakeSuite -LocalAppData $env:LOCALAPPDATA
            $runner=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
            {& $runner -Mode Seal -SuiteId $set.SuiteId -ExpectedPlanSha256 $set.PlanSha256 -WhatIf} |
                Should -Throw '*Seal accepts only exact SuiteId and plan SHA*'
        } finally {$env:LOCALAPPDATA=$old}
    }
    It 'ordinary Seal works with the same fake five-witness file set' {
        $old=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $set=Initialize-OPA265BW4k1aFakeSuite -LocalAppData $env:LOCALAPPDATA
            $runner=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k1RealOneShotMove.ps1'
            $result=& $runner -Mode Seal -SuiteId $set.SuiteId -ExpectedPlanSha256 $set.PlanSha256
            $result.Count | Should -Be 5
            $result.EvidenceSetSha256 | Should -Match '^[a-f0-9]{64}$'
        } finally {$env:LOCALAPPDATA=$old}
    }
    It 'preserves dry-run intent through read-only preflight and stops before any claim/Move' {
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
}
