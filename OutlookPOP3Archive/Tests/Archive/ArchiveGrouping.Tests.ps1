BeforeAll {
    . "$PSScriptRoot/../../Core/Archive/ArchiveGrouping.ps1"
}

Describe 'Get-OPAArchiveGroupParts' {
    It 'None returns no parts' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-05-17') -Grouping 'None') | Should -Be @()
    }
    It 'Year returns the four-digit year' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-05-17') -Grouping 'Year') | Should -Be @('2024')
    }
    It 'YearQuarter maps months to correct quarters' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-01-15') -Grouping 'YearQuarter') | Should -Be @('2024','Q1')
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-03-31') -Grouping 'YearQuarter') | Should -Be @('2024','Q1')
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-04-01') -Grouping 'YearQuarter') | Should -Be @('2024','Q2')
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-12-31') -Grouping 'YearQuarter') | Should -Be @('2024','Q4')
    }
    It 'YearMonth returns year and zero-padded month' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2024-03-05') -Grouping 'YearMonth') | Should -Be @('2024','03')
    }
}

Describe 'Get-OPAArchiveTargetPath' {
    It 'builds quarter path with folder hierarchy below the store root' {
        $r = Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2023-08-11') -SourceFolderName 'Inbox' `
            -SourceFolderPath '\\Store@example.com\Inbox' -Grouping 'YearQuarter'
        $r | Should -Be '2023\Q3\Inbox'
    }
    It 'keeps nested folder hierarchy below the store root' {
        $r = Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2023-08-11') -SourceFolderName 'Sub' `
            -SourceFolderPath '\\Store\Projects\Sub' -Grouping 'Year'
        $r | Should -Be '2023\Projects\Sub'
    }
    It 'falls back to the folder name when no path is given' {
        $r = Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2023-08-11') -SourceFolderName 'Inbox' -Grouping 'None'
        $r | Should -Be 'Inbox'
    }
}
