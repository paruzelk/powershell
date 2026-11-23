#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1')
    $script:run='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
    function New-ARCH3x1FakePrepared {
        return [pscustomobject]@{
            Manifest=[pscustomobject]@{
                RunId=$script:run;SourcePst='C:\OPA-FAKE\info@stios.ru.pst'
                TargetPstPreview='C:\OPA-FAKE\info@stios.ru.Archive-2020-03.pst'
                BatchSize=10
            }
            Seal=[pscustomobject]@{Rows=@()}
            Review=[pscustomobject]@{PreparedIntentCount=10}
        }
    }
}
Describe 'ARCH3x1 bounded original real ten provider Move, fail closed at every irreversible boundary' {
    It 'public CLI exposes exact Plan Audit Move Status, never Resume/Auto' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3x1.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Audit','Move','Status'\)"
        $s | Should -Match 'ConfirmTenRealMoves'
        $s | Should -Match 'ExpectedPreflightDigest'
        $s | Should -Not -Match "ValidateSet\('.*Resume"
    }
    It 'public entry loads actual original real batch core, no missing dot-source path' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3x1.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1'
        Test-Path -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') | Should -BeTrue
    }
    It 'batch core reuses historical ARCH3w1/ARCH3v without replacing original verifiers' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Test-OPA265ARCH3w1PreparedReadback -Layout'
        $s | Should -Match 'Get-OPA265ARCH3x1bPartsProof -Manifest'
        $s | Should -Match 'Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest'
        $s | Should -Match 'Assert-OPA265ARCH3iFullWitnessPinned -Witness'
    }
    It 'batch core calls original Year and archive PST creator only after durable writer entry' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $idxWrite=$s.IndexOf('$writerSha=Write-OPA265ARCH3cJsonOnce -Path')
        $idxPst=$s.IndexOf('$archive=New-OPAArchivePst -Namespace')
        $idxFolder=$s.IndexOf('$folder=Get-OPAArchiveFolder -ArchiveStore')
        $idxWrite | Should -BeGreaterThan 0
        $idxPst | Should -BeGreaterThan $idxWrite
        $idxFolder | Should -BeGreaterThan $idxPst
        $s | Should -Match 'ARCH3oRequireNewUnusedPst'
    }
    It 'one original MailMover provider invocation is preceded by immutable claim' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Write-OPA265ARCH3cJsonOnce -Path \(Join-Path \$layout.Root \(\$prefix\+'
        $s | Should -Match 'Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail'
        $s | Should -Match 'PreviousMoveReceiptSha256'
    }
    It 'original MailMover provider is a genuine COM-only route and writes invocation before Move' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $start=$s.IndexOf('function Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall')
        $start | Should -BeGreaterThan 0
        $new=$s.Substring($start)
        $new | Should -Match '\$Mail -isnot \[__ComObject\]'
        $new.IndexOf('Write-OPA265ARCH3cJsonOnce -Path') | Should -BeLessThan $new.IndexOf('$moved=$Mail.Move($Folder)')
        $new | Should -Not -Match 'FinalReleaseComObject\(\$parent\)'
    }
    It 'real provider refuses fake PSCustomObject before touching any operator evidence' {
        $fake=[pscustomobject]@{Class=43;EntryID='00000000DEADBEEFDEADBEEF'}
        {Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail $fake -Folder $fake -RunId $script:run -Ordinal 1 -ClaimSha256 ('a'*64)} | Should -Throw
    }
    It 'real provider rejects unpinned or arbitrary RunId before COM access' {
        $fake=[pscustomobject]@{Class=43;EntryID='00000000DEADBEEFDEADBEEF'}
        {Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail $fake -Folder $fake -RunId ([guid]::NewGuid().ToString('D')) -Ordinal 1 -ClaimSha256 ('a'*64)} | Should -Throw
    }
    It 'provider requires canonical lowercase external claim SHA' {
        $fake=[pscustomobject]@{Class=43;EntryID='00000000DEADBEEFDEADBEEF'}
        {Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail $fake -Folder $fake -RunId $script:run -Ordinal 1 -ClaimSha256 'wrong'} | Should -Throw
    }
    It 'layout refuses any arbitrary operator RunId rather than creating a new attempt' {
        {Get-OPA265ARCH3x1Layout -RunId ([guid]::NewGuid().ToString('D'))} | Should -Throw
    }
    It 'preparation refuses missing source, manifest and journal SHA pins before Outlook' {
        {Get-OPA265ARCH3x1PinnedPrepared -RunId $script:run -SealSha256 'a' -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64)} | Should -Throw
    }
    It 'Status works offline when no writer entry exists' {
        $l=[pscustomobject]@{RunId=$script:run;Root=(Join-Path $TestDrive 'no-writer');WriterEntryPath=(Join-Path $TestDrive 'no-writer\writer-entry.json')}
        $s=Get-OPA265ARCH3x1ReadOnlyStatus -Layout $l
        $s.Status | Should -BeExactly 'NoRealTenWriterEntry'
        $s.Claims | Should -Be 0
        $s.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'Status rejects extraneous arguments rather than live Outlook fallback' {
        {Invoke-OPA265ARCH3x1RealTen -Mode Status -RunId $script:run -SealSha256 ('a'*64)} | Should -Throw
    }
    It 'Status rejects an unknown pre-existing writer evidence filename' {
        $folder=Join-Path $TestDrive 'unknown-evidence'
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::WriteAllText((Join-Path $folder 'intruder.txt'),'x')
        Mock Assert-OPA265ARCH2c2PrivateWorkspaceAcl {$true}
        $l=[pscustomobject]@{RunId=$script:run;Root=$folder;WriterEntryPath=(Join-Path $folder 'writer-entry.json')}
        {Get-OPA265ARCH3x1ReadOnlyStatus -Layout $l} | Should -Throw
        $source=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $source | Should -Match '\[IO.FileAttributes\]::ReparsePoint'
    }
    It 'Status rejects directory present without a protected writer entry' {
        $folder=Join-Path $TestDrive 'empty-root'
        [void][IO.Directory]::CreateDirectory($folder)
        Mock Assert-OPA265ARCH2c2PrivateWorkspaceAcl {$true}
        $l=[pscustomobject]@{RunId=$script:run;Root=$folder;WriterEntryPath=(Join-Path $folder 'writer-entry.json')}
        {Get-OPA265ARCH3x1ReadOnlyStatus -Layout $l} | Should -Throw
    }
    It 'Plan loads protected ten intents offline and leaves original PST alone' {
        Mock Get-OPA265ARCH3x1PinnedPrepared {return (New-ARCH3x1FakePrepared)}
        Mock Open-OPA265ARCH2dSession {throw 'Outlook must not be touched'}
        $r=Invoke-OPA265ARCH3x1RealTen -Mode Plan -RunId $script:run -SealSha256 ('a'*64) -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64)
        $r.PreparedIntentCount | Should -Be 10
        $r.RealOutlookContacted | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'Move requires an explicit operator flag before connecting Outlook' {
        Mock Get-OPA265ARCH3x1PinnedPrepared {return (New-ARCH3x1FakePrepared)}
        Mock Open-OPA265ARCH2dSession {throw 'Outlook must not be touched'}
        {Invoke-OPA265ARCH3x1RealTen -Mode Move -RunId $script:run -SealSha256 ('a'*64) -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64) -ExpectedPreflightDigest ('d'*64)} | Should -Throw
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'Move rejects missing externally observed Audit PreflightDigest before any writer' {
        Mock Get-OPA265ARCH3x1PinnedPrepared {return (New-ARCH3x1FakePrepared)}
        Mock Open-OPA265ARCH2dSession {throw 'Outlook must not be touched'}
        {Invoke-OPA265ARCH3x1RealTen -Mode Move -RunId $script:run -SealSha256 ('a'*64) -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64) -ConfirmTenRealMoves} | Should -Throw
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'Move -WhatIf prevents Outlook access and real PST or workspace writes' {
        Mock Get-OPA265ARCH3x1PinnedPrepared {return (New-ARCH3x1FakePrepared)}
        Mock Open-OPA265ARCH2dSession {throw 'Outlook must not be touched'}
        $r=Invoke-OPA265ARCH3x1RealTen -Mode Move -RunId $script:run -SealSha256 ('a'*64) -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64) -ExpectedPreflightDigest ('d'*64) -ConfirmTenRealMoves -WhatIf
        $r.Status | Should -BeExactly 'WhatIfBeforeRealOutlookPstOrWriterWrites'
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'Preflight refuses already occupied Part3 before original MailMover' {
        $part=Join-Path $TestDrive 'info@stios.ru.Archive-2020-03.pst'
        [IO.File]::WriteAllText($part,'SYNTHETIC')
        $pre=[pscustomobject]@{
            Manifest=[pscustomobject]@{SourcePst=(Join-Path $TestDrive 'info@stios.ru.pst');TargetPstPreview=$part}
            Seal=[pscustomobject]@{}
        }
        Mock Assert-OPA265ARCH3fRealTestSource {return (Join-Path $TestDrive 'info@stios.ru.pst')}
        Mock Get-OPA265ARCH3x1bPartsProof {throw 'Must not reach Outlook'}
        {Get-OPA265ARCH3x1RealPreflight -Prepared $pre -ManifestSha256 ('a'*64) -JournalSha256 ('b'*64)} | Should -Throw
        Should -Invoke Get-OPA265ARCH3x1bPartsProof -Exactly -Times 0
    }
    It 'Preflight checks original shared index and full source semantic witnesses' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst'
        $s | Should -Match 'Get-OPA265ARCH3dOriginalWitnessHash|Assert-OPA265ARCH3iFullWitnessPinned'
        $s | Should -Match 'OriginalArchiveVerifierPart2Passed'
    }
    It 'real Move returns remain uncommitted until independent Outlook restart' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'IndependentPostRestartVerified=\$false'
        $s | Should -Match 'OriginalJournalReconciled=\$false'
        $s | Should -Not -Match '(?m)^\s*Add-OPADuplicateEntry\s'
        $s | Should -Not -Match '(?m)^\s*Write-OPAOperationJournalEvent\s'
        $s | Should -Not -Match '(?m)^\s*Invoke-OPAArchiveResume'
    }
    It 'both writer and provider forbid automatic retries on partial claims' {
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $mover=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $core | Should -Match 'NEVER REPLAY'
        $core | Should -Match 'AutomaticMoveRetryAllowed=\$false'
        $mover | Should -Match 'NO RETRY'
        $mover | Should -Match 'ARCH3x1 actual COM Move result indeterminate'
    }
    It 'all added or modified PowerShell files use UTF8 BOM including original MailMover' {
        foreach($p in @('Invoke-ARCH3x1.ps1','Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1','Tests/Archive/ARCH3x1RealTenOriginalMailMover.Tests.ps1','Core/Archive/MailMover.ps1')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:root $p))
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
        }
    }
}
