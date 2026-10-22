BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'Core/Runtime/ComManager.ps1')
    . (Join-Path $root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $root 'Core/Archive/ArchiveSelector.ps1')

    function New-OPASelectorTestFolder {
        param([switch]$FailSort)
        $rows = @(
            [pscustomobject]@{Class=43;EntryID='E1';Subject='one';ReceivedTime=[datetime]'2020-01-01';SentOn=[datetime]'2020-01-01';CreationTime=[datetime]'2020-01-01';SenderEmailAddress='a@x';Size=10},
            [pscustomobject]@{Class=43;EntryID='E2';Subject='two';ReceivedTime=[datetime]'2021-01-01';SentOn=[datetime]'2021-01-01';CreationTime=[datetime]'2021-01-01';SenderEmailAddress='b@x';Size=20},
            [pscustomobject]@{Class=43;EntryID='E3';Subject='three';ReceivedTime=[datetime]'2025-01-01';SentOn=[datetime]'2025-01-01';CreationTime=[datetime]'2025-01-01';SenderEmailAddress='c@x';Size=30}
        )
        $items = [pscustomobject]@{Rows=$rows;Count=3;FailSort=[bool]$FailSort}
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$index)
            return $this.Rows[$index-1]
        }
        $items | Add-Member -MemberType ScriptMethod -Name Restrict -Value {
            param([string]$filter)
            throw 'Restrict unavailable in mock'
        }
        $items | Add-Member -MemberType ScriptMethod -Name Sort -Value {
            param([string]$property,[bool]$descending)
            if ($this.FailSort) { throw 'Sort unavailable in mock' }
            $this.Rows = @($this.Rows | Sort-Object ReceivedTime)
        }
        return [pscustomobject]@{
            Items=$items;Name='Inbox';EntryID='INBOX';Store=$null;FolderPath='\\source\Inbox'
        }
    }
}

Describe 'FIX11 trustworthy Plan age exclusion diagnostics' {
    It 'labels the excluded count incomplete after optimized Sort stops at cutoff' {
        $folder = New-OPASelectorTestFolder
        $result = Get-OPAArchiveCandidates -SourceFolder $folder -Limit 50 -OlderThanCutoff ([datetime]'2024-01-01') -Diagnostics
        $result.EligibleByAge | Should -Be 2
        $result.ExcludedByAgeExact | Should -BeFalse
    }
    It 'counts excluded age exactly when full scan is necessary' {
        $folder = New-OPASelectorTestFolder -FailSort
        $result = Get-OPAArchiveCandidates -SourceFolder $folder -Limit 50 -OlderThanCutoff ([datetime]'2024-01-01') -Diagnostics
        $result.EligibleByAge | Should -Be 2
        $result.ExcludedByAge | Should -Be 1
        $result.ExcludedByAgeExact | Should -BeTrue
    }
    It 'treats disabled age cutoff as zero excluded' {
        $folder = New-OPASelectorTestFolder
        $result = Get-OPAArchiveCandidates -SourceFolder $folder -Limit 50 -Diagnostics
        $result.EligibleByAge | Should -Be 3
        $result.ExcludedByAge | Should -Be 0
        $result.ExcludedByAgeExact | Should -BeTrue
    }
}
