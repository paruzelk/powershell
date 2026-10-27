#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    $script:BW3cPaths=@(
        (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1'),
        (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3bIndependentMoveAudit.ps1'),
        (Join-Path $PSScriptRoot 'BW3bIndependentPostMoveAudit.Tests.ps1')
    )
    $script:BW3cAuditText=Get-Content -LiteralPath $script:BW3cPaths[1] -Raw
}
Describe 'BW3c pinned Cyrillic SourcePst valid in Windows PowerShell 5.1 without BOM' {
    It 'constructs exact five-letter Russian directory from Unicode code points' {
        $r=(-join @([char]0x0424,[char]0x0430,[char]0x0439,[char]0x043B,[char]0x044B))
        $r.Length | Should -Be 5
        ([int][char]$r[0]) | Should -Be 1060
        ([int][char]$r[4]) | Should -Be 1099
    }
    It 'matches the independent ASCII-driven expected source path exactly' {
        $r=(-join @([char]0x0424,[char]0x0430,[char]0x0439,[char]0x043B,[char]0x044B))
        $path='C:\Users\bogoderov_e\Documents\'+$r+' Outlook\info@stios.ru.pst'
        (Get-OPA265BW3bPinnedIdentity).SourcePst | Should -BeExactly $path
    }
    It 'rejects a same-named file inside a different PST folder' {
        $expected=[string](Get-OPA265BW3bPinnedIdentity).SourcePst
        ($expected -cne $expected.Replace('Documents','Downloads')) | Should -BeTrue
    }
    It 'rejects changed character case in the pinned path' {
        $expected=[string](Get-OPA265BW3bPinnedIdentity).SourcePst
        ($expected -cne $expected.Replace('Outlook','OUTLOOK')) | Should -BeTrue
    }
    It 'pins the same old RunId, OperationId, WorkerRequestId and SHA256' {
        $p=Get-OPA265BW3bPinnedIdentity
        $p.RunId | Should -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
        $p.OperationId | Should -BeExactly '9bd83da2-d47e-404f-a4fd-792852b58dec'
        $p.WorkerRequestId | Should -BeExactly '24553e9c-fa09-497f-b42d-4329ebe27021'
        $p.JournalSha256 | Should -BeExactly '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
    }
    It 'contains no non-ASCII bytes in the read-only audit .ps1 source' {
        foreach($path in $script:BW3cPaths) {
            $data=[IO.File]::ReadAllBytes($path)
            (@($data | Where-Object { $_ -gt 127 })).Count | Should -Be 0
        }
    }
    It 'retains strict exact-case source path preflight from pinned identity' {
        $script:BW3cAuditText | Should -Match '\$SourcePst -cne \[string\]\$pinned\.SourcePst'
        $script:BW3cAuditText | Should -Not -Match 'Documents\\[^\x00-\x7F]'
    }
    It 'rejects wrong RunId before any Outlook COM' {
        $runCheck=$script:BW3cAuditText.IndexOf('$RunId -cne $pinned.RunId')
        $comCall=$script:BW3cAuditText.IndexOf("GetActiveObject('Outlook.Application')")
        $runCheck | Should -BeGreaterThan 0
        ($runCheck -lt $comCall) | Should -BeTrue
    }
    It 'rejects changed JournalSha256 before any Outlook COM' {
        $shaCheck=$script:BW3cAuditText.IndexOf('$ExpectedJournalSha256 -cne $pinned.JournalSha256')
        $comCall=$script:BW3cAuditText.IndexOf("GetActiveObject('Outlook.Application')")
        $shaCheck | Should -BeGreaterThan 0
        ($shaCheck -lt $comCall) | Should -BeTrue
    }
    It 'still requires read-only Review gate without -Execute' {
        $script:BW3cAuditText | Should -Match '-not \$Review'
        $script:BW3cAuditText | Should -Not -Match 'ConfirmBW3SyntheticMove'
    }
    It 'still does not dispatch a Worker, retry a Move or finish the journal' {
        $script:BW3cAuditText | Should -Not -Match 'Invoke-OPAWorkerControlledOperation|Write-OPA264Live6ReconciledLocked|Write-OPAOperationJournalEvent|\$mail\.Move\('
    }
    It 'parses audit and pinned helper cleanly in native PowerShell 5.1' {
        foreach($path in $script:BW3cPaths[0..1]) {
            $tokens=$null; $errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
