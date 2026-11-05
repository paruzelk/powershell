#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a2ReadOnlyPilotObservation265.ps1')
    $script:forensic=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a2FailedPilotReadOnlyReview.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a2Observation {
        return @{
            PstFilePresent=$true;IntentPresent=$true
            TargetStoreMatches=1;TestFolderMatches=1;TestFolderItemCount=1
            Candidates=@([pscustomobject]@{
                SubjectMatches=$true;ClassIsMail=$true;ItemEntryIdPresent=$true
                ParentStoreMatches=$true;ParentFolderMatches=$true
                GetItemFromIdMatches=$true
            })
        }
    }
}
Describe 'BW4k7v2a2 READ-ONLY original failed-pilot forensics policy' {
    It 'classifies one exact previously saved pilot without granting a retry' {
        $a=New-BW4k7v2a2Observation
        $r=Test-OPA265BW4k7v2a2PilotObservation @a
        $r.Status | Should -BeExactly 'OnePilotPresentInExactTargetFolderAfterFailure'
    }
    It 'does not pretend to identify original failed predicate after recovery' {
        $a=New-BW4k7v2a2Observation
        (Test-OPA265BW4k7v2a2PilotObservation @a).ExactOriginalPredicateThatFailedProven | Should -BeFalse
    }
    It 'classifies zero target items without assuming other store misroute' {
        $a=New-BW4k7v2a2Observation;$a.TestFolderItemCount=0;$a.Candidates=@()
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'NoMatchingPilotInTargetFolderNoCrossStoreSearch'
    }
    It 'rejects multiple pilot subjects' {
        $a=New-BW4k7v2a2Observation;$a.TestFolderItemCount=2
        $a.Candidates=@($a.Candidates[0],$a.Candidates[0])
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'MultiplePilotSubjectsManualReview'
    }
    It 'reports missing attached target without auto-mounting' {
        $a=New-BW4k7v2a2Observation;$a.TargetStoreMatches=0
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'TargetPstNotUniquelyMountedNoWrites'
    }
    It 'reports two mounted target references without guessing' {
        $a=New-BW4k7v2a2Observation;$a.TargetStoreMatches=2
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'TargetPstNotUniquelyMountedNoWrites'
    }
    It 'reports missing original intent' {
        $a=New-BW4k7v2a2Observation;$a.IntentPresent=$false
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'NoOriginalIntentManualReview'
    }
    It 'reports missing test PST' {
        $a=New-BW4k7v2a2Observation;$a.PstFilePresent=$false
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'TargetPstFileMissingManualReview'
    }
    It 'reports no matching test folder without scanning other PST' {
        $a=New-BW4k7v2a2Observation;$a.TestFolderMatches=0
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'TestFolderMissingOrDuplicatedNoWrites'
    }
    It 'reports unreadable target count' {
        $a=New-BW4k7v2a2Observation;$a.TestFolderItemCount=-1
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'TestFolderCountUnreadableNoWrites'
    }
    It 'reports saved pilot with parent StoreID mismatch as unresolved' {
        $a=New-BW4k7v2a2Observation;$a.Candidates[0].ParentStoreMatches=$false
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'PilotPresentButOriginalPredicateUnresolvedManualReview'
    }
    It 'reports saved pilot with parent EntryID mismatch as unresolved' {
        $a=New-BW4k7v2a2Observation;$a.Candidates[0].ParentFolderMatches=$false
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'PilotPresentButOriginalPredicateUnresolvedManualReview'
    }
    It 'reports by-ID lookup failure without claiming corruption' {
        $a=New-BW4k7v2a2Observation;$a.Candidates[0].GetItemFromIdMatches=$false
        (Test-OPA265BW4k7v2a2PilotObservation @a).Status | Should -BeExactly 'PilotPresentButOriginalPredicateUnresolvedManualReview'
    }
    It 'never grants writer or production status' {
        $a=New-BW4k7v2a2Observation;$r=Test-OPA265BW4k7v2a2PilotObservation @a
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'forensic controller never uses AddStoreEx or Save or Move or Send or Delete' {
        $script:forensic | Should -Not -Match '\.(AddStoreEx|AddStore|Save|Move|Send|Delete|CreateItem)\s*\('
    }
    It 'forensic controller uses active Outlook without creating a fresh session' {
        $script:forensic | Should -Match "GetActiveObject\('Outlook.Application'\)"
        $script:forensic | Should -Not -Match 'New-Object -ComObject|CreateObject\('
    }
    It 'reads only pinned target PST folder not default Drafts' {
        $script:forensic | Should -Match 'GetRootFolder\(\)'
        $script:forensic | Should -Match '\$folder\.Items\.Item\(\$k\)'
        $script:forensic | Should -Not -Match 'GetDefaultFolder'
    }
    It 'retains sealed original intent and never recreates it' {
        $script:forensic | Should -Match 'one-pilot-intent.json absent'
        $script:forensic | Should -Not -Match 'Write-OPA265BW4k7v2a1JsonOnce'
    }
    It 'requires original POP3 delivery StoreID from immutable intent' {
        $script:forensic | Should -Match 'intent.Pop3DeliveryStoreId'
    }
}