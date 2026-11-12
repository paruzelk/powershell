#requires -Version 5.1
# ARCH2c2: synthetic ACL, exclusive lease, and crash-residue policy.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2bSemanticWitness.ps1')
    function New-ARCH2c2TestRoot {
        param([string]$Name)
        $folder=Join-Path $TestDrive $Name
        [void][IO.Directory]::CreateDirectory($folder)
        return $folder
    }
    function New-ARCH2c2FakeMail {
        param([object[]]$Attachments=@())
        $items=[pscustomobject]@{Count=$Attachments.Count; Entries=@($Attachments)}
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$Index)
            return $this.Entries[$Index-1]
        }
        return [pscustomobject]@{Attachments=$items}
    }
    function New-ARCH2c2FakeAttachment {
        param([byte[]]$Content=[byte[]]@(0,1,2,255))
        $attachment=[pscustomobject]@{
            FileName='защищённый.bin'
            Type=1
            Size=[int64]$Content.Length
            Content=$Content
        }
        $attachment | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$Path)
            [IO.File]::WriteAllBytes($Path,[byte[]]$this.Content)
        }
        return $attachment
    }
}
Describe 'ARCH2c2 private NTFS workspace and exclusive lifetime lease (no Outlook)' {
    It 'creates a private workspace with protected ACL and current user ownership' {
        $root=New-ARCH2c2TestRoot 'protected-acl'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        try {
            (Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $workspace.WorkspacePath) | Should -BeTrue
            ([IO.Directory]::GetAccessControl($workspace.WorkspacePath)).AreAccessRulesProtected | Should -BeTrue
        }
        finally { Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspace }
    }
    It 'holds the lease exclusively while the attachment workspace is active' {
        $root=New-ARCH2c2TestRoot 'exclusive'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        try {
            { [IO.File]::Open($workspace.LeasePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None) } | Should -Throw
            (Get-OPA265ARCH2c2ObservedLeaseState -WorkspacePath $workspace.WorkspacePath) | Should -BeExactly 'HeldOrUnavailable'
        }
        finally { Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspace }
    }
    It 'removes the empty workspace and lease on normal close' {
        $root=New-ARCH2c2TestRoot 'close'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        $path=$workspace.WorkspacePath
        $lease=$workspace.LeasePath
        [IO.File]::Exists($lease) | Should -BeTrue
        Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspace
        [IO.File]::Exists($lease) | Should -BeFalse
        [IO.Directory]::Exists($path) | Should -BeFalse
    }
    It 'does not allow cleanup of unexpected payloads or perform recursive deletion' {
        $root=New-ARCH2c2TestRoot 'unknown-content'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        $unexpected=Join-Path $workspace.WorkspacePath 'unknown-content.bin'
        try {
            [IO.File]::WriteAllBytes($unexpected,[byte[]]@(3,2,1))
            {Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspace} | Should -Throw
            [IO.File]::Exists($unexpected) | Should -BeTrue
            [IO.Directory]::Exists($workspace.WorkspacePath) | Should -BeTrue
        }
        finally {
            if([IO.Directory]::Exists($workspace.WorkspacePath)){
                Remove-Item -LiteralPath $workspace.WorkspacePath -Recurse -Force
            }
        }
    }
    It 'rejects a workspace using inherited or permissive ACL instead of private ACL' {
        $root=New-ARCH2c2TestRoot 'inherited-acl'
        $unsafe=Join-Path $root 'not-secure'
        [void][IO.Directory]::CreateDirectory($unsafe)
        { Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $unsafe } | Should -Throw
    }
    It 'reports a held lease in the unchanged read-only orphan inventory' {
        $root=New-ARCH2c2TestRoot 'active-inventory'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        try {
            $rows=@(Get-OPA265ARCH2c1AttachmentWorkspaceInventory -TemporaryDirectory $root)
            $rows.Count | Should -Be 1
            $rows[0].LeaseState | Should -BeExactly 'HeldOrUnavailable'
            $rows[0].RequiresManualReview | Should -BeTrue
            $rows[0].AutomaticallyDeleted | Should -BeFalse
            [IO.File]::Exists($workspace.LeasePath) | Should -BeTrue
        }
        finally { Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspace }
    }
    It 'reports a released lease after simulated interruption without deleting payloads' {
        $root=New-ARCH2c2TestRoot 'simulated-crash'
        $workspace=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root
        $payload=Join-Path $workspace.WorkspacePath 'left-after-crash.bin'
        try {
            [IO.File]::WriteAllBytes($payload,[byte[]]@(0,8,255,10))
            $workspace.LeaseStream.Dispose()
            (Get-OPA265ARCH2c2ObservedLeaseState -WorkspacePath $workspace.WorkspacePath) | Should -BeExactly 'NotHeldAtObservation'
            $rows=@(Get-OPA265ARCH2c1AttachmentWorkspaceInventory -TemporaryDirectory $root)
            $rows.Count | Should -Be 1
            $rows[0].LeaseState | Should -BeExactly 'NotHeldAtObservation'
            $rows[0].RequiresManualReview | Should -BeTrue
            [IO.File]::Exists($payload) | Should -BeTrue
        }
        finally {
            if([IO.Directory]::Exists($workspace.WorkspacePath)){
                Remove-Item -LiteralPath $workspace.WorkspacePath -Recurse -Force
            }
        }
    }
    It 'reports missing lease without guessing the workspace is safe to delete' {
        $root=New-ARCH2c2TestRoot 'missing-lease'
        $owned=Join-Path $root ('OPA-ARCH2c1-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($owned)
        (Get-OPA265ARCH2c2ObservedLeaseState -WorkspacePath $owned) | Should -BeExactly 'Absent'
        $rows=@(Get-OPA265ARCH2c1AttachmentWorkspaceInventory -TemporaryDirectory $root)
        $rows.Count | Should -Be 1
        $rows[0].LeaseState | Should -BeExactly 'Absent'
        $rows[0].AutomaticallyDeleted | Should -BeFalse
    }
    It 'does not accept spoofed workspace identity for cleanup' {
        $root=New-ARCH2c2TestRoot 'spoof'
        $fake=[pscustomobject]@{
            WorkspacePath=(Join-Path $root 'not-an-OPA-workspace')
            LeasePath=(Join-Path $root 'not-an-OPA-workspace/.opa-lease')
            LeaseStream=$null
        }
        {Close-OPA265ARCH2c2PrivateWorkspace -Workspace $fake} | Should -Throw
        [IO.Directory]::Exists($root) | Should -BeTrue
    }
    It 'rejects a missing local temporary root before creating any workspace' {
        $root=Join-Path $TestDrive 'missing-root'
        {New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $root} | Should -Throw
        [IO.Directory]::Exists($root) | Should -BeFalse
    }
    It 'uses the ACL-protected path for real synthetic attachment byte hashes' {
        $root=New-ARCH2c2TestRoot 'main-witness'
        $mail=New-ARCH2c2FakeMail -Attachments @((New-ARCH2c2FakeAttachment))
        $rows=@(Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -TemporaryDirectory $root -MaxAttachmentBytes 4096)
        $rows.Count | Should -Be 1
        $rows[0].PayloadByteCount | Should -Be 4
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'cleans both payload and secure workspace after normal SaveAsFile failure' {
        $root=New-ARCH2c2TestRoot 'saveas-error'
        $attachment=New-ARCH2c2FakeAttachment
        $attachment | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Force -Value {
            param([string]$Path)
            [IO.File]::WriteAllBytes($Path,[byte[]]$this.Content)
            throw 'Synthetic error after writing bytes'
        }
        $mail=New-ARCH2c2FakeMail -Attachments @($attachment)
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -TemporaryDirectory $root -MaxAttachmentBytes 4096} | Should -Throw
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'fails closed when temporary attachment count exceeds bounded limit' {
        $root=New-ARCH2c2TestRoot 'over-count'
        $attachments=@(1..3 | ForEach-Object {New-ARCH2c2FakeAttachment})
        $mail=New-ARCH2c2FakeMail -Attachments $attachments
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -TemporaryDirectory $root -MaxAttachmentCount 2} | Should -Throw
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'retains ARCH2a DEV writer closure and never enables production or blind retry' {
        $entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $entry | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
        $module=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2bSemanticWitness.ps1') -Raw -Encoding UTF8
        $module | Should -Match 'New-OPA265ARCH2c2PrivateWorkspace'
        $module | Should -Match 'Close-OPA265ARCH2c2PrivateWorkspace'
        $module | Should -Not -Match 'Remove-Item\s+.*-Recurse'
    }
}
