#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4jSuitePlan265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4jMultiFormatWitness265.ps1')
    function New-BW4jUnitWitness {
        param([object]$Case,[string]$SuiteId,[string]$StoreId='111111',
              [string]$EntryId='AAAA')
        $atts=@()
        if($Case.ExpectedAttachmentCount -eq 1){
            $atts=@([pscustomobject][ordered]@{
                Index=1;FileName='test.bin';ByteCount=[long]$Case.MinimumAttachmentBytes;
                Sha256=('a'*64)
            })
        }
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
            SuiteId=$SuiteId
            CaseName=$Case.Name
            TestId=$Case.TestId
            ProfileName='Outlook'
            EntryId=$EntryId
            FolderEntryId='AABB'
            StoreId=$StoreId
            InternetMessageId='<fixture@example.invalid>'
            SearchKeySha256=('b'*64)
            SubjectUtf8Sha256=('c'*64)
            SenderUtf8Sha256=('d'*64)
            BodyUtf8Sha256=('e'*64)
            HtmlBodyUtf8Sha256=('f'*64)
            SubjectLength=64;BodyLength=256;HtmlBodyLength=512
            Size=[long]8760
            ReceivedUtcTicks=[long]639289630550000000
            Attachments=@($atts)
            OutlookMoveExecuted=$false
            ProductionReady=$false
        }
    }
}
Describe 'BW4j fresh five-scenario synthetic manifest security and hygiene' {
    BeforeEach {$script:plan=New-OPA265BW4jPlan}
    It 'creates five distinct declared cases' {
        $script:plan.Cases.Count | Should -Be 5
        (Assert-OPA265BW4jPlan -Plan $script:plan) | Should -BeTrue
    }
    It 'includes plain small, Unicode, HTML, small attachment and 256 KiB attachment' {
        @($script:plan.Cases.Name) -join ',' | Should -BeExactly 'PlainSmall,UnicodePlain,HtmlBody,Attachment1K,Attachment256K'
    }
    It 'uses a fresh GUID for suite and all tests' {
        $other=New-OPA265BW4jPlan
        $other.SuiteId | Should -Not -BeExactly $script:plan.SuiteId
        @($script:plan.Cases.TestId | Select-Object -Unique).Count | Should -Be 5
    }
    It 'never offers automatic Send or Move' {
        $script:plan.AutomaticSendAllowed | Should -BeFalse
        $script:plan.AutomaticMoveAllowed | Should -BeFalse
        $script:plan.ProductionReady | Should -BeFalse
    }
    It 'rejects changing a case name' {
        $script:plan.Cases[0].Name='Different'
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects reusing a previous test GUID' {
        $script:plan.Cases[1].TestId=$script:plan.Cases[0].TestId
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects changed fixture subject' {
        $script:plan.Cases[2].Subject='hello'
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects adding a sixth case' {
        $script:plan.Cases+=@($script:plan.Cases[0])
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects enabling Send' {
        $script:plan.AutomaticSendAllowed=$true
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects enabling Move' {
        $script:plan.AutomaticMoveAllowed=$true
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'rejects invalid noncanonical suite path' {
        {Get-OPA265BW4jPlanPath -SuiteId 'not-a-guid' -LocalAppData $TestDrive} | Should -Throw
    }
    It 'pins attachment byte floor' {
        $script:plan.Cases[4].MinimumAttachmentBytes=1024
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
    It 'refuses auto-created production-ready suite' {
        $script:plan.ProductionReady=$true
        {Assert-OPA265BW4jPlan -Plan $script:plan} | Should -Throw
    }
}
Describe 'BW4j exact synthetic Subject/Body/HTML/attachment fixture markers' {
    BeforeAll {$script:plan=New-OPA265BW4jPlan}
    It 'accepts plain fixture without attachments' {
        $case=$script:plan.Cases[0]
        (Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body $case.Marker -HtmlBody '' -AttachmentCount 0) | Should -BeTrue
    }
    It 'rejects old BW4g message subject even if marker matches' {
        $case=$script:plan.Cases[0]
        {Assert-OPA265BW4jFixture -Case $case -Subject 'OPA265 BW4e1 FRESH TEST' -Body $case.Marker -HtmlBody '' -AttachmentCount 0} | Should -Throw
    }
    It 'requires Unicode body for UnicodePlain' {
        $case=$script:plan.Cases[1]
        {Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body $case.Marker -HtmlBody '' -AttachmentCount 0} | Should -Throw
        (Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body ($case.Marker+' Привет мир') -HtmlBody '' -AttachmentCount 0) | Should -BeTrue
    }
    It 'requires HTML markup for HtmlBody' {
        $case=$script:plan.Cases[2]
        {Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body $case.Marker -HtmlBody 'plain' -AttachmentCount 0} | Should -Throw
        (Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body $case.Marker -HtmlBody '<html><body>test</body></html>' -AttachmentCount 0) | Should -BeTrue
    }
    It 'rejects missing attachment in attachment fixture' {
        $case=$script:plan.Cases[3]
        {Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body $case.Marker -HtmlBody '' -AttachmentCount 0} | Should -Throw
    }
    It 'rejects tampered TestId marker' {
        $case=$script:plan.Cases[0]
        {Assert-OPA265BW4jFixture -Case $case -Subject $case.Subject -Body 'wrong marker' -HtmlBody '' -AttachmentCount 0} | Should -Throw
    }
}
Describe 'BW4j independent zero, one or multi binary attachment hashes' {
    It 'returns zero witnesses when no attachments' {
        $mail=[pscustomobject]@{Attachments=[pscustomobject]@{Count=0}}
        @(Get-OPA265BW4jAttachments -Mail $mail).Count | Should -Be 0
    }
    It 'rejects unsafe attachment count before saving anything' {
        $mail=[pscustomobject]@{Attachments=[pscustomobject]@{Count=3}}
        {Get-OPA265BW4jAttachments -Mail $mail} | Should -Throw
    }
    It 'hashes one bounded synthetic attachment and cleans ephemeral file' {
        $file=[pscustomobject]@{FileName='test.bin';Type=1;Size=1024}
        $file | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$path)
            [IO.File]::WriteAllBytes($path,(New-Object byte[] 1024))
        }
        $items=[pscustomobject]@{Count=1;First=$file}
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$index)
            if($index -ne 1){throw 'invalid test index'}
            return $this.First
        }
        $mail=[pscustomobject]@{Attachments=$items}
        $r=@(Get-OPA265BW4jAttachments -Mail $mail)
        $r.Count | Should -Be 1
        $r[0].ByteCount | Should -Be 1024
        $r[0].Sha256 | Should -BeExactly (Get-OPA265BW4jSha256 -Bytes (New-Object byte[] 1024))
    }
    It 'rejects by-reference attachment before any SaveAsFile' {
        $file=[pscustomobject]@{FileName='reference.bin';Type=4;Size=1024}
        $items=[pscustomobject]@{Count=1;First=$file}
        $items | Add-Member ScriptMethod Item {param([int]$index) return $this.First}
        $mail=[pscustomobject]@{Attachments=$items}
        {Get-OPA265BW4jAttachments -Mail $mail} | Should -Throw
    }
    It 'rejects unsafe source attachment path/name' {
        $file=[pscustomobject]@{FileName='..\bad.exe';Type=1;Size=1024}
        $items=[pscustomobject]@{Count=1;First=$file}
        $items | Add-Member ScriptMethod Item {param([int]$index) return $this.First}
        $mail=[pscustomobject]@{Attachments=$items}
        {Get-OPA265BW4jAttachments -Mail $mail} | Should -Throw
    }
}
Describe 'BW4j multi-format source/destination content SHA and MAPI size comparison' {
    BeforeEach {
        $script:plan=New-OPA265BW4jPlan
        $script:case=$script:plan.Cases[3]
        $script:src=New-BW4jUnitWitness -Case $script:case -SuiteId $script:plan.SuiteId
        $script:dst=New-BW4jUnitWitness -Case $script:case -SuiteId $script:plan.SuiteId -StoreId '222222' -EntryId 'BBBB'
    }
    It 'accepts the exact 22-field witness and one attachment' {
        (Assert-OPA265BW4jWitness -Witness $script:src -Case $script:case -SuiteId $script:plan.SuiteId) | Should -BeTrue
    }
    It 'reports all checked fields matched without declaring byte equality' {
        $r=Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId
        $r.Status | Should -BeExactly 'AllCheckedFieldsMatchReadOnly'
        $r.FullMAPIByteEqualityProven | Should -BeFalse
        $r.CanRetryMove | Should -BeFalse
    }
    It 'identifies +38 byte MAPI size change without automatic acceptance' {
        $script:dst.Size=[long]8798
        $r=Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId
        $r.Status | Should -BeExactly 'OnlyMAPIMessageSizeChangedNeedsManualReview'
        $r.DeltaSize | Should -Be 38
        $r.ProductionReady | Should -BeFalse
    }
    It 'identifies binary attachment corruption despite matching MAPI size' {
        $script:dst.Attachments[0].Sha256=('0'*64)
        (Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId).AttachmentsMatch | Should -BeFalse
    }
    It 'identifies HTML body drift independently of plain Body' {
        $script:dst.HtmlBodyUtf8Sha256=('0'*64)
        (Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId).Status | Should -BeExactly 'ContentOrAttachmentDriftNeedsManualReview'
    }
    It 'detects changed sender even when subject is unchanged' {
        $script:dst.SenderUtf8Sha256=('0'*64)
        (Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId).SenderMatches | Should -BeFalse
    }
    It 'does not trust same original and target PST StoreId' {
        $script:dst.StoreId=$script:src.StoreId
        (Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId).Status | Should -BeExactly 'BlockedIdentityOrStoreMismatch'
    }
    It 'does not trust changed InternetMessageId' {
        $script:dst.InternetMessageId='<wrong@example.invalid>'
        (Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId).IdentityMatches | Should -BeFalse
    }
    It 'refuses forged mail moved-by-comparison evidence' {
        $script:src.OutlookMoveExecuted=$true
        {Compare-OPA265BW4jWitness -Source $script:src -Destination $script:dst -Case $script:case -SuiteId $script:plan.SuiteId} | Should -Throw
    }
    It 'rejects unexpected fake production field in original witness' {
        $script:src | Add-Member NoteProperty AutoMove $true
        {Assert-OPA265BW4jWitness -Witness $script:src -Case $script:case -SuiteId $script:plan.SuiteId} | Should -Throw
    }
}
Describe 'BW4j manifest and source evidence CreateNew with native UTF8 BOM' {
    BeforeAll {$script:originalAppData=$env:LOCALAPPDATA}
    AfterAll {$env:LOCALAPPDATA=$script:originalAppData}
    It 'writes manifest once, preserves exact SHA and blocks a second write' {
        $env:LOCALAPPDATA=$TestDrive
        $plan=New-OPA265BW4jPlan
        $r=Write-OPA265BW4jPlanOnce -Plan $plan
        [IO.File]::Exists($r.PlanPath) | Should -BeTrue
        ([IO.File]::ReadAllBytes($r.PlanPath)[0]) | Should -Be 239
        $real=(Get-FileHash -LiteralPath $r.PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $r.PlanSha256 | Should -BeExactly $real
        {Write-OPA265BW4jPlanOnce -Plan $plan} | Should -Throw
    }
    It 'generates deterministic evidence path for exact suite + test' {
        $plan=New-OPA265BW4jPlan
        $path=Get-OPA265BW4jEvidencePath -SuiteId $plan.SuiteId -TestId $plan.Cases[0].TestId -LocalAppData 'C:\Temp'
        $path | Should -Match 'OutlookPOP3Archive-BW4j-Suites'
        $path | Should -Match 'fixture-'
    }
}
Describe 'BW4j refuses unauthorized production automation and historical journal writes' {
    BeforeAll {$script:code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4jSuiteReadOnly.ps1'))}
    It 'never invokes Outlook Move/Send in diagnostic wrapper' {
        $script:code | Should -Not -Match '(?i)\$mail\.Move\('
        $script:code | Should -Not -Match '(?i)\$.*\.Send\('
    }
    It 'requires original seven-file BW3a historic Intent check' {
        $script:code | Should -Match 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly'
        $script:code | Should -Match 'SevenHistoricalEvidenceHashesUnchanged'
    }
    It 'does not write original journal or BW4g/BW4i immutable claims' {
        $script:code | Should -Not -Match 'Write-OPAOperationJournal'
        $script:code | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
        $script:code | Should -Not -Match 'Write-OPA265BW4iDecisionOnce'
    }
    It 'supports only explicit plan, source evidence and read-only destination witness' {
        $script:code | Should -Match 'NewPlan'
        $script:code | Should -Match 'SourceCapture'
        $script:code | Should -Match 'DestinationReview'
        $script:code | Should -Not -Match 'ConfirmOneShotSyntheticMove'
    }
}
