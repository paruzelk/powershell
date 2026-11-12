#requires -Version 5.1
# ARCH2c3: standalone synthetic policy tests; does NOT launch Outlook or mount PST.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2c3DisposableProbePolicy.ps1')
    $script:guid='11111111-2222-4a33-8b44-5555555555aa'
    $script:root=$env:LOCALAPPDATA
    $script:sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    function New-ARCH2c3Layout {
        param([string]$FixtureKind='BW4k7v2a1')
        return Get-OPA265ARCH2c3DisposableLayout -SuiteId $script:guid -FixtureKind $FixtureKind -LocalAppData $script:root
    }
    function New-ARCH2c3Stores {
        param([object]$Layout)
        return @(
            [pscustomobject]@{StoreId='DEFAULT';FilePath='C:\mail\default.pst'},
            [pscustomobject]@{StoreId='TEST';FilePath=[string]$Layout.TestPstPath}
        )
    }
    function New-ARCH2c3Scope {
        param([object]$Layout,[object[]]$Stores=(New-ARCH2c3Stores -Layout $Layout),
              [object[]]$Accounts=@([pscustomobject]@{DeliveryStoreId='DEFAULT'}),
              [string]$DefaultStoreId='DEFAULT',[string]$Profile='Outlook')
        return Test-OPA265ARCH2c3StoreScope -Layout $Layout -ActualProfileName $Profile -DefaultStoreId $DefaultStoreId -Stores $Stores -Accounts $Accounts
    }
}
Describe 'ARCH2c3 disposable Outlook COM preflight policy (no PST or Outlook contact)' {
    It 'derives exact previously existing BW4k7v2a1 disposable PST layout' {
        $l=New-ARCH2c3Layout
        $l.TestPstPath | Should -BeLike ('*OutlookPOP3Archive-BW4k7v2a1-ExistingProfile*')
        $l.TestPstPath | Should -BeLike ('*OPA265-BW4k7v2a1-'+$script:guid+'.pst')
        $l.TestFolderName | Should -BeExactly ('OPA265-BW4k7v2a1-'+$script:guid)
        $l.WriterPermit | Should -BeFalse
    }
    It 'supports a previously created BW4k7v isolated fixture without widening to any PST path' {
        $l=New-ARCH2c3Layout -FixtureKind 'BW4k7v'
        $l.TestPstPath | Should -BeLike ('*OutlookPOP3Archive-BW4k7v-Isolated*')
        $l.TestFolderName | Should -BeExactly ('OPA265-BW4k7v-'+$script:guid)
    }
    It 'rejects malformed GUID' {
        {Get-OPA265ARCH2c3DisposableLayout -SuiteId 'oops' -FixtureKind 'BW4k7v' -LocalAppData $script:root} | Should -Throw
    }
    It 'rejects uppercase/noncanonical suite GUID' {
        {Get-OPA265ARCH2c3DisposableLayout -SuiteId $script:guid.ToUpperInvariant() -FixtureKind 'BW4k7v' -LocalAppData $script:root} | Should -Throw
    }
    It 'rejects a forged production PST path' {
        $l=New-ARCH2c3Layout
        $l.TestPstPath='C:\Users\someone\Documents\info@stios.ru.pst'
        {Assert-OPA265ARCH2c3DisposableLayout -Layout $l} | Should -Throw
    }
    It 'rejects wrong test folder and mismatched suite layout' {
        $l=New-ARCH2c3Layout
        $l.TestFolderName='Inbox'
        {Assert-OPA265ARCH2c3DisposableLayout -Layout $l} | Should -Throw
    }
    It 'does not create a missing PST on a Review request' {
        $l=New-ARCH2c3Layout
        {Assert-OPA265ARCH2c3DisposableLayout -Layout $l -RequirePst} | Should -Throw
        [IO.File]::Exists($l.TestPstPath) | Should -BeFalse
    }
    It 'accepts the original isolated layout with no PST requirement for Plan' {
        $l=New-ARCH2c3Layout
        (Assert-OPA265ARCH2c3DisposableLayout -Layout $l) | Should -BeTrue
    }
    It 'approves only uniquely attached test PST when no account uses it for delivery' {
        $l=New-ARCH2c3Layout
        $r=New-ARCH2c3Scope -Layout $l
        $r.Approved | Should -BeTrue
        $r.TargetStoreId | Should -BeExactly 'TEST'
        $r.WriterPermit | Should -BeFalse
    }
    It 'rejects wrong Outlook profile' {
        $l=New-ARCH2c3Layout
        (New-ARCH2c3Scope -Layout $l -Profile 'Other').ReasonCodes | Should -Contain 'WrongProfile'
    }
    It 'rejects target PST as default store' {
        $l=New-ARCH2c3Layout
        (New-ARCH2c3Scope -Layout $l -DefaultStoreId 'TEST').ReasonCodes | Should -Contain 'TargetIsDefaultStore'
    }
    It 'rejects target PST as an email account delivery store' {
        $l=New-ARCH2c3Layout
        $ac=@([pscustomobject]@{DeliveryStoreId='TEST'})
        (New-ARCH2c3Scope -Layout $l -Accounts $ac).ReasonCodes | Should -Contain 'TargetIsAccountDeliveryStore'
    }
    It 'rejects missing attached disposable PST' {
        $l=New-ARCH2c3Layout
        $stores=@([pscustomobject]@{StoreId='DEFAULT';FilePath='C:\mail\default.pst'})
        (New-ARCH2c3Scope -Layout $l -Stores $stores).ReasonCodes | Should -Contain 'TargetPstNotUniquelyAttached'
    }
    It 'rejects ambiguous repeated store path' {
        $l=New-ARCH2c3Layout
        $stores=New-ARCH2c3Stores -Layout $l
        $stores+=([pscustomobject]@{StoreId='TEST2';FilePath=[string]$l.TestPstPath})
        (New-ARCH2c3Scope -Layout $l -Stores $stores).ReasonCodes | Should -Contain 'TargetPstNotUniquelyAttached'
    }
    It 'rejects absent target StoreID' {
        $l=New-ARCH2c3Layout
        $stores=@([pscustomobject]@{StoreId='DEFAULT';FilePath='C:\mail\default.pst'},
                  [pscustomobject]@{StoreId='';FilePath=[string]$l.TestPstPath})
        (New-ARCH2c3Scope -Layout $l -Stores $stores).ReasonCodes | Should -Contain 'NoTargetStoreId'
    }
    It 'matches an exact external attachment payload digest and length' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4096})
        $r=Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 $script:sha -ExpectedPayloadBytes 4096
        $r.CriticalPayloadMatches | Should -BeTrue
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects an altered attachment even when byte length is unchanged' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=('b'*64);PayloadByteCount=4096})
        (Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 $script:sha -ExpectedPayloadBytes 4096).CriticalPayloadMatches | Should -BeFalse
    }
    It 'rejects changed byte length even with matching SHA256 field' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4095})
        (Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 $script:sha -ExpectedPayloadBytes 4096).CriticalPayloadMatches | Should -BeFalse
    }
    It 'rejects a second attachment instead of accepting a partial witness' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4096},
             [pscustomobject]@{Index=2;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4096})
        (Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 $script:sha -ExpectedPayloadBytes 4096).CriticalPayloadMatches | Should -BeFalse
    }
    It 'rejects malformed independent SHA256' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4096})
        {Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 'not-a-hash' -ExpectedPayloadBytes 4096} | Should -Throw
    }
    It 'rejects a negative independent attachment length' {
        $w=@([pscustomobject]@{Index=1;Type=1;PayloadSha256=$script:sha;PayloadByteCount=4096})
        {Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $w -ExpectedPayloadSha256 $script:sha -ExpectedPayloadBytes -1} | Should -Throw
    }
    It 'requires both a changed process ID and start UTC ticks to accept restart' {
        (Assert-OPA265ARCH2c3RestartedOutlook -OriginalProcessId 123 -OriginalProcessStartUtcTicks 1000 -ObservedProcessId 456 -ObservedProcessStartUtcTicks 2000) | Should -BeTrue
    }
    It 'rejects fake restart with same PID' {
        {Assert-OPA265ARCH2c3RestartedOutlook -OriginalProcessId 123 -OriginalProcessStartUtcTicks 1000 -ObservedProcessId 123 -ObservedProcessStartUtcTicks 2000} | Should -Throw
    }
    It 'rejects fake restart with identical process start ticks' {
        {Assert-OPA265ARCH2c3RestartedOutlook -OriginalProcessId 123 -OriginalProcessStartUtcTicks 1000 -ObservedProcessId 456 -ObservedProcessStartUtcTicks 1000} | Should -Throw
    }
    It 'does not invoke Outlook or PST writers in the main read-only probe controller' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265ARCH2c3DisposableAttachmentProbe.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.AddStore(Ex)?\s*\('
        $s | Should -Not -Match '\.(Move|Copy|Delete|Send|Save)\s*\('
        $s | Should -Match "GetActiveObject\('Outlook.Application'\)"
        $s | Should -Match 'Get-OPA265ARCH2bAttachmentWitnesses'
        $s | Should -Match 'Assert-OPA265ARCH2c3RestartedOutlook'
        $s | Should -Not -Match 'New-Object\s+-ComObject\s+Outlook'
    }
    It 'does not unlock Archive Resume Auto in the application entrypoint' {
        $entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $entry | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
}
