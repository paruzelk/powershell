#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2aPristineInventoryPolicy265.ps1')
    $script:controller=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2IsolatedPilotPreflight.ps1') -Raw -Encoding UTF8
    function Copy-OPA265BW4k7v2aRows {
        return @(
            [pscustomobject]@{FolderId='ROOT';Depth=0;ItemCount=0;ChildFolderCount=2}
            [pscustomobject]@{FolderId='INBOX';Depth=1;ItemCount=0;ChildFolderCount=0}
            [pscustomobject]@{FolderId='DRAFTS';Depth=1;ItemCount=0;ChildFolderCount=0}
        )
    }
}
Describe 'BW4k7v2a READ-ONLY pristine visible PST gate before pilot' {
    It 'accepts a fully observed empty store folder tree' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).Pristine | Should -BeTrue
    }
    It 'counts all three folders' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).FolderCount | Should -Be 3
    }
    It 'rejects a Drafts item as not pristine' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[2].ItemCount=1
        (Test-OPA265BW4k7v2aPristineInventory -Rows $rows).Pristine | Should -BeFalse
    }
    It 'rejects a nonempty Inbox' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[1].ItemCount=4
        (Test-OPA265BW4k7v2aPristineInventory -Rows $rows).VisibleItemCount | Should -Be 4
    }
    It 'rejects items in root' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[0].ItemCount=1
        (Test-OPA265BW4k7v2aPristineInventory -Rows $rows).ReasonCodes | Should -Contain 'PreexistingVisibleOutlookItems'
    }
    It 'never claims physical byte level PST emptiness' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).PhysicalPstEmptinessProven | Should -BeFalse
    }
    It 'never grants production writer permission' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).WriterPermit | Should -BeFalse
    }
    It 'never marks production ready' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).ProductionReady | Should -BeFalse
    }
    It 'never allows fallback to another PST' {
        (Test-OPA265BW4k7v2aPristineInventory -Rows (Copy-OPA265BW4k7v2aRows)).AutomaticRecoveryOrFallbackAllowed | Should -BeFalse
    }
    It 'rejects incomplete child enumeration' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[0].ChildFolderCount=3
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects duplicate folder IDs' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[2].FolderId='INBOX'
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects missing folder ID' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[1].FolderId=''
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects negative item counts' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[1].ItemCount=-1
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects negative child folder counts' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[0].ChildFolderCount=-1
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects multiple roots' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[1].Depth=0
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects an unrooted first folder' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[0].Depth=1
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects missing mandatory item count' {
        $rows=Copy-OPA265BW4k7v2aRows
        [void]$rows[1].PSObject.Properties.Remove('ItemCount')
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
        $rows=Copy-OPA265BW4k7v2aRows
        $rows[1].ItemCount=$null
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects empty inventory' {
        {Test-OPA265BW4k7v2aPristineInventory -Rows @()} | Should -Throw
    }
    It 'limits to 128 folder observations' {
        $rows=@(for($i=0;$i -lt 129;$i++){[pscustomobject]@{FolderId=('id'+$i);Depth=$([int]($i -gt 0));ItemCount=0;ChildFolderCount=$([int]($i -eq 0)*128)}})
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'rejects unresolved descendants at maximum depth' {
        $rows=Copy-OPA265BW4k7v2aRows; $rows[2].Depth=32; $rows[2].ChildFolderCount=1
        {Test-OPA265BW4k7v2aPristineInventory -Rows $rows} | Should -Throw
    }
    It 'controller calls pristine validation before first folder write' {
        $p=$script:controller.IndexOf('Test-OPA265BW4k7v2aPristineInventory')
        $w=$script:controller.IndexOf('$pstRoot.Folders.Add')
        $p | Should -BeGreaterThan 0
        $w | Should -BeGreaterThan $p
    }
    It 'controller fails closed above 128 COM folders' {
        $script:controller | Should -Match 'pristine inventory exceeds 128 folders'
    }
    It 'controller never calls pilot Move Send Delete' {
        $script:controller | Should -Not -Match '\$pilot\.(Move|Send|Delete)\s*\('
    }
}
