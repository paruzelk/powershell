#requires -Version 5.1
# ARCH2c1: no Outlook and no production PST contact.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2bSemanticWitness.ps1')
    function New-ARCH2c1Collection {
        param([object[]]$Items=@())
        $c=[pscustomobject]@{Count=$Items.Count; Entries=@($Items)}
        $c | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$index)
            return $this.Entries[$index-1]
        }
        return $c
    }
    function New-ARCH2c1Attachment {
        param([byte[]]$Content=[byte[]]@(1,2,3,4),[switch]$ThrowAfterWrite)
        $a=[pscustomobject]@{
            FileName='содержимое.bin'; Type=1
            Size=[int64]$Content.Length
            Content=$Content
            ThrowAfterWrite=[bool]$ThrowAfterWrite
        }
        $a | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$path)
            [IO.File]::WriteAllBytes($path,[byte[]]$this.Content)
            if($this.ThrowAfterWrite){throw 'Synthetic SaveAsFile interrupted after partial write.'}
        }
        return $a
    }
    function New-ARCH2c1Mail {
        param([object[]]$Attachments=@())
        return [pscustomobject]@{Attachments=(New-ARCH2c1Collection -Items $Attachments)}
    }
    function New-ARCH2c1TempRoot {
        param([string]$Name)
        $path=Join-Path $TestDrive $Name
        [void][IO.Directory]::CreateDirectory($path)
        return $path
    }
}
Describe 'ARCH2c1 isolated temporary attachment workspace — synthetic fail-closed' {
    It 'hashes actual bytes and removes its temporary workspace on success' {
        $root=New-ARCH2c1TempRoot -Name 'successful'
        $actual=@(Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail -Attachments @((New-ARCH2c1Attachment))) -TemporaryDirectory $root -MaxAttachmentBytes 4096)
        $actual.Count | Should -Be 1
        $actual[0].PayloadByteCount | Should -Be 4
        $actual[0].PayloadSha256 | Should -BeExactly '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a'
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'cleans partial SaveAsFile output and workspace after exception' {
        $root=New-ARCH2c1TempRoot -Name 'saveas-failure'
        $attachment=New-ARCH2c1Attachment -ThrowAfterWrite
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail -Attachments @($attachment)) -TemporaryDirectory $root -MaxAttachmentBytes 4096} | Should -Throw
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
        @([IO.File]::GetFiles($root)).Count | Should -Be 0
    }
    It 'cleans multiple attachment copies after a complete witness' {
        $root=New-ARCH2c1TempRoot -Name 'two-attachments'
        $mail=New-ARCH2c1Mail -Attachments @((New-ARCH2c1Attachment),(New-ARCH2c1Attachment -Content ([byte[]]@(255,0))))
        $rows=@(Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -TemporaryDirectory $root -MaxAttachmentBytes 4096)
        $rows.Count | Should -Be 2
        $rows[1].PayloadByteCount | Should -Be 2
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'keeps zero-attachment processing free from workspace residue' {
        $root=New-ARCH2c1TempRoot -Name 'zero'
        $rows=@(Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail) -TemporaryDirectory $root)
        $rows.Count | Should -Be 0
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'fails closed on oversized actual bytes even if Outlook reports a small size' {
        $root=New-ARCH2c1TempRoot -Name 'actual-oversize'
        $a=New-ARCH2c1Attachment -Content ([byte[]](New-Object byte[] 4097))
        $a.Size=4
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail -Attachments @($a)) -TemporaryDirectory $root -MaxAttachmentBytes 4096} | Should -Throw
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'fails closed on unsupported type and leaves no temporary workspace' {
        $root=New-ARCH2c1TempRoot -Name 'type-rejected'
        $a=New-ARCH2c1Attachment
        $a.Type=5
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail -Attachments @($a)) -TemporaryDirectory $root -MaxAttachmentBytes 4096} | Should -Throw
        @([IO.Directory]::GetDirectories($root)).Count | Should -Be 0
    }
    It 'rejects missing temporary root before contacting attachments' {
        $root=Join-Path $TestDrive 'not-created'
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail (New-ARCH2c1Mail) -TemporaryDirectory $root} | Should -Throw
    }
    It 'inventories only specifically named residual workspaces without reading private payloads' {
        $root=New-ARCH2c1TempRoot -Name 'inventory'
        $owned=Join-Path $root ('OPA-ARCH2c1-'+[guid]::NewGuid().ToString('N'))
        $unrelated=Join-Path $root 'unrelated-folder'
        [void][IO.Directory]::CreateDirectory($owned)
        [void][IO.Directory]::CreateDirectory($unrelated)
        $payload=Join-Path $owned 'OPA-ARCH2b-partial.bin'
        [IO.File]::WriteAllBytes($payload,[byte[]]@(1,255,0,99))
        $items=@(Get-OPA265ARCH2c1AttachmentWorkspaceInventory -TemporaryDirectory $root)
        $items.Count | Should -Be 1
        $items[0].WorkspacePath | Should -BeExactly $owned
        $items[0].RequiresManualReview | Should -BeTrue
        $items[0].AutomaticallyDeleted | Should -BeFalse
        [IO.File]::Exists($payload) | Should -BeTrue
        [IO.Directory]::Exists($unrelated) | Should -BeTrue
    }
    It 'does not include lookalike names in the orphan inventory' {
        $root=New-ARCH2c1TempRoot -Name 'lookalikes'
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'OPA-ARCH2c1-other'))
        [void][IO.Directory]::CreateDirectory((Join-Path $root ('OPA-ARCH2c1-'+[guid]::NewGuid().ToString('N')+'-bad')))
        @(Get-OPA265ARCH2c1AttachmentWorkspaceInventory -TemporaryDirectory $root).Count | Should -Be 0
    }
    It 'retains the ARCH2a writer guard and original Move preflight' {
        $entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $entry | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
        $mover=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $mover | Should -Match 'Get-OPA265ARCH2bMailSemanticWitness -Mail \$item'
        $mover | Should -Match 'Sync-OPAStepJournalStreams'
    }
}
