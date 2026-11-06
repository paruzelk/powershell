#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a3DraftsEvidence265.ps1')
    $script:live=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a3FindOriginalPilotDraftsReadOnly.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a3Rows {
        return @(
            [pscustomobject]@{StoreIdSha256=('a'*64);Status='Read';Matches=@()}
            [pscustomobject]@{StoreIdSha256=('b'*64);Status='NoDraftsFolder';Matches=@()}
            [pscustomobject]@{StoreIdSha256=('c'*64);Status='Read';Matches=@()}
        )
    }
    function New-BW4k7v2a3Candidate {
        param([string]$Hash=('a'*64))
        return [pscustomobject]@{
            StoreIdSha256=$Hash;SubjectMatches=$true;ClassIsMail=$true
        }
    }
}
Describe 'BW4k7v2a3 exact-subject existing Drafts location diagnostic no Outlook writers' {
    It 'classifies a complete search with no matching Drafts pilot' {
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows (New-BW4k7v2a3Rows)).Status |
            Should -BeExactly 'NoPilotFoundInCheckedDraftsFolders'
    }
    It 'counts all observed connected stores' {
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows (New-BW4k7v2a3Rows)).InspectedStoreCount | Should -Be 3
    }
    It 'recognizes Drafts not available in a store without claiming a failure' {
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows (New-BW4k7v2a3Rows)).AbsentDraftsFolderCount | Should -Be 1
    }
    It 'recognizes one exact matching synthetic MailItem' {
        $rows=New-BW4k7v2a3Rows;$rows[0].Matches=@(New-BW4k7v2a3Candidate)
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows).Status |
            Should -BeExactly 'SinglePilotLocatedInDraftsReadOnly'
    }
    It 'counts one exact candidate and preserves provenance' {
        $rows=New-BW4k7v2a3Rows;$rows[0].Matches=@(New-BW4k7v2a3Candidate)
        $result=Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows
        $result.ExactSubjectMatchCount | Should -Be 1
        $result.MatchCandidates[0].StoreIdSha256 | Should -BeExactly ('a'*64)
    }
    It 'flags multiple exact pilot matches as ambiguous' {
        $rows=New-BW4k7v2a3Rows;$rows[0].Matches=@(New-BW4k7v2a3Candidate)
        $rows[2].Matches=@(New-BW4k7v2a3Candidate -Hash ('c'*64))
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows).Status |
            Should -BeExactly 'MultipleMatchingPilotsManualReview'
    }
    It 'flags unreadable Drafts before declaring a negative search complete' {
        $rows=New-BW4k7v2a3Rows;$rows[2].Status='ProviderError'
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows).Status |
            Should -BeExactly 'IncompleteDraftsSearchNoConclusion'
    }
    It 'flags a single candidate as incomplete if another store raised an error' {
        $rows=New-BW4k7v2a3Rows;$rows[0].Matches=@(New-BW4k7v2a3Candidate)
        $rows[2].Status='ProviderError'
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows).Status |
            Should -BeExactly 'SinglePilotFoundButOtherDraftsChecksIncomplete'
    }
    It 'rejects a store that reported a match limit exceeded' {
        $rows=New-BW4k7v2a3Rows;$rows[2].Status='MatchLimitExceeded'
        (Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows).AnyDraftsInspectionIncomplete |
            Should -BeTrue
    }
    It 'rejects zero store observations' {
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows @()} | Should -Throw
    }
    It 'rejects more than 32 store observations' {
        $rows=@(for($i=0;$i -lt 33;$i++){
            [pscustomobject]@{StoreIdSha256=('{0:x64}' -f $i);Status='Read';Matches=@()}
        })
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects repeated hashed StoreIDs' {
        $rows=New-BW4k7v2a3Rows;$rows[2].StoreIdSha256=$rows[0].StoreIdSha256
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects an invalid hashed StoreID length' {
        $rows=New-BW4k7v2a3Rows;$rows[0].StoreIdSha256='wrong'
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects a null store observation' {
        $rows=New-BW4k7v2a3Rows;$rows[1]=$null
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects missing status in observation' {
        $rows=New-BW4k7v2a3Rows;[void]$rows[0].PSObject.Properties.Remove('Status')
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects a match recorded in a store where Drafts was unavailable' {
        $rows=New-BW4k7v2a3Rows;$rows[1].Matches=@(New-BW4k7v2a3Candidate -Hash ('b'*64))
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects an unrelated subject returned by Restrict' {
        $rows=New-BW4k7v2a3Rows
        $rows[0].Matches=@(New-BW4k7v2a3Candidate)
        $rows[0].Matches[0].SubjectMatches=$false
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects candidate belonging to a different StoreID' {
        $rows=New-BW4k7v2a3Rows;$rows[0].Matches=@(New-BW4k7v2a3Candidate -Hash ('f'*64))
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'rejects more than eight matching subjects in one store' {
        $rows=New-BW4k7v2a3Rows
        $rows[0].Matches=@(for($i=0;$i -lt 9;$i++){New-BW4k7v2a3Candidate})
        {Test-OPA265BW4k7v2a3DraftsEvidence -Rows $rows} | Should -Throw
    }
    It 'never claims absence from non-Drafts folders or historical Save proof' {
        $r=Test-OPA265BW4k7v2a3DraftsEvidence -Rows (New-BW4k7v2a3Rows)
        $r.ExactMatchOutsideDraftsProvenAbsent | Should -BeFalse
        $r.ActualPreviousSaveDestinationHistoricallyProven | Should -BeFalse
    }
    It 'never grants permission to retry or to run production worker' {
        $r=Test-OPA265BW4k7v2a3DraftsEvidence -Rows (New-BW4k7v2a3Rows)
        $r.OriginalSuiteIdRetryPermitted | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'controller pins original intent SHA and never calls Save Move or AddStore' {
        $script:live | Should -Match 'ExpectedIntentSha256'
        $script:live | Should -Match 'Intent SHA256 mismatch'
        $script:live | Should -Not -Match '\.(Save|Move|AddStoreEx|AddStore|Send|Delete|CreateItem)\s*\('
    }
    It 'controller queries exact subject in each store Drafts, not other mail folders' {
        $script:live | Should -Match 'GetDefaultFolder\(16\)'
        $script:live | Should -Match '\.Restrict\('
        $script:live | Should -Not -Match '\$ns\.GetDefaultFolder\('
        $script:live | Should -Not -Match '\$root\.Folders'
    }
    It 'controller never scans other message bodies' {
        $script:live | Should -Not -Match '\$item\.Body|\$item\.HTMLBody|\$item\.Attachments'
    }
}