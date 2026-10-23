#requires -Version 5.1
BeforeAll {
    $script:restart = Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA263RestartReadOnly.ps1'
    $script:source = [IO.File]::ReadAllText($script:restart)

    # Inspect executable AST nodes, not raw source. The prior test falsely
    # rejected a harmless COMMENT that contained "New-Object -ComObject".
    $tokens = $null
    $errors = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:restart, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw ("Restart verifier syntax error: {0}" -f [string]$errors[0].Message)
    }
    $script:commands = @($script:ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true))
    $script:methodCalls = @($script:ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true))
}
Describe '2.6.3 restart read-only COM test safety policy' {
    It 'requires an existing journal and one unresolved MailMove Intent' {
        $script:source | Should -Match 'Read-OPAOperationJournal'
        $script:source | Should -Match 'Resolve-OPAOperationRecovery'
        $script:source | Should -Match "pending.Count -ne 1"
    }

    It 'uses attached Outlook only and does not create, attach or detach PSTs' {
        $script:source | Should -Match 'GetActiveObject'
        $newComObjects = @($script:commands | Where-Object {
            if ($_.GetCommandName() -ine 'New-Object') { return $false }
            foreach ($element in $_.CommandElements) {
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                    [string]$element.ParameterName -ieq 'ComObject') {
                    return $true
                }
            }
            return $false
        })
        $newComObjects.Count | Should -Be 0
        $storeMutation = @($script:methodCalls | Where-Object {
            @('AddStore','AddStoreEx','RemoveStore') -icontains [string]$_.Member.Value
        })
        $storeMutation.Count | Should -Be 0
    }

    It 'does not mutate items or append journal terminal events' {
        $mailMutation = @($script:methodCalls | Where-Object {
            @('Move','Copy','Delete','Quit') -icontains [string]$_.Member.Value
        })
        $mailMutation.Count | Should -Be 0
        $journalMutation = @($script:commands | Where-Object {
            $_.GetCommandName() -ieq 'Write-OPAOperationJournalEvent'
        })
        $journalMutation.Count | Should -Be 0
    }

    It 'requires exact persisted StoreID and destination PST path' {
        $script:source | Should -Match 'SourceStoreId'
        $script:source | Should -Match 'GetFullPath'
        $script:source | Should -Match 'StoreID'
        $script:source | Should -Match 'ExpectedPath'
        $script:source | Should -Match 'Do NOT substitute another store'
    }

    It 'enforces journal SHA-256 unchanged and reject automatic retry' {
        $script:source | Should -Match 'hashBefore'
        $script:source | Should -Match 'hashAfter'
        $script:source | Should -Match 'AutomaticRetryAllowed'
        $script:source | Should -Match 'ProvenMoved'
        $script:source | Should -Match 'RequiresManualReview'
    }

    It 'fails closed if Outlook shows a different state after restart' {
        $script:source | Should -Match 'ExpectedStatus'
        $script:source | Should -Match 'Restart read-only classification mismatch'
    }
}
