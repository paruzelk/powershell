#requires -Version 5.1
BeforeAll {
    $script:path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3gManualSizeAcceptance.ps1'
    $script:source=Get-Content -LiteralPath $script:path -Raw
    $script:tokens=$null
    $script:errors=$null
    $script:ast=[Management.Automation.Language.Parser]::ParseFile($script:path,[ref]$script:tokens,[ref]$script:errors)
}
Describe 'BW3g1: PS5.1 case-insensitive switch Record vs acceptance object variable regression' {
    It 'PowerShell script parses without any syntax errors' {
        @($script:errors).Count | Should -Be 0
    }
    It 'keeps explicit Record switch as a parameter for one-time write' {
        $script:source | Should -Match '\[switch\]\$Record'
        $script:source | Should -Match "'Record'"
    }
    It 'never assigns to a variable named Record in any capitalization' {
        $assignments=@($script:ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
            [string]$node.Left.VariablePath.UserPath -ieq 'Record'
        },$true))
        $assignments.Count | Should -Be 0
    }
    It 'stores PSCustomObject in distinct acceptance entry local variable' {
        $script:source | Should -Match '\$sizeAcceptanceEntry=New-OPA265BW3gManualAcceptance'
        $script:source | Should -Match 'Assert-OPA265BW3gManualAcceptance -Record \$sizeAcceptanceEntry'
        $script:source | Should -Match 'Write-OPA265BW3gCreateNewRecord -Paths \$paths -Record \$sizeAcceptanceEntry'
    }
    It 'retains a working native PS5.1 switch after building an acceptance entry' {
        function Test-BW3g1CaseInsensitiveRecordParameter {
            param([switch]$Record)
            $sizeAcceptanceEntry=[pscustomobject]@{Confirmed=$true}
            return [pscustomobject]@{SwitchValue=[bool]$Record;RecordValue=$sizeAcceptanceEntry}
        }
        $result=Test-BW3g1CaseInsensitiveRecordParameter -Record
        $result.SwitchValue | Should -BeTrue
        $result.RecordValue.Confirmed | Should -BeTrue
    }
    It 'preserves explicit token comparison and write-once safety barrier' {
        $tokenIndex=$script:source.IndexOf('$ExactSizeAcceptance -cne [string]$pinned.ExactAcknowledgment')
        $writeIndex=$script:source.IndexOf('Write-OPA265BW3gCreateNewRecord -Paths $paths')
        $existingIndex=$script:source.IndexOf('BW3g approval record already exists. Never overwrite or retry.')
        $tokenIndex | Should -BeGreaterThan 0
        $existingIndex | Should -BeGreaterThan 0
        ($tokenIndex -lt $writeIndex) | Should -BeTrue
        ($existingIndex -lt $writeIndex) | Should -BeTrue
    }
}
