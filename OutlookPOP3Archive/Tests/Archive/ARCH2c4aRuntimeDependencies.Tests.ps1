#requires -Version 5.1
# ARCH2c4a integration regression: real ARCH2c4 module bootstrap and ORIGINAL
# ARCH2b witness call using a fake Outlook MailItem. Previous ARCH2c4 tests
# dot-sourced policy ONLY and missed the Get-OPAInternetMessageId dependency.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2c4OneShotCore.ps1')
    function New-OPA265ARCH2c4aCollection {
        param([object[]]$Items=@())
        $o=[pscustomobject]@{Count=$Items.Count; Entries=@($Items)}
        $o | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$i) return $this.Entries[$i-1]
        }
        return $o
    }
    function New-OPA265ARCH2c4aFakeMail {
        param([string]$Body='Тест исходного письма',
              [int64]$Size=1400,
              [object[]]$Attachments=@())
        $pa=[pscustomobject]@{}
        $pa|Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
            param([string]$tag)
            if($tag -match '0x1035001E$'){return '<original-2020@example.test>'}
            throw 'Property unavailable'
        }
        return [pscustomobject]@{
            Class=43;PropertyAccessor=$pa
            Subject='Тест архива Ω';SenderEmailAddress='sender@example.test'
            To='Recipient <recipient@example.test>';CC='';BCC=''
            Body=$Body;HTMLBody=('<p>'+$Body+'</p>')
            ReceivedTime=[datetime]'2020-01-30T02:28:22Z'
            SentOn=[datetime]'2020-01-30T02:25:00Z'
            UnRead=$false;Importance=1;Sensitivity=0;Categories=''
            Recipients=(New-OPA265ARCH2c4aCollection)
            Attachments=(New-OPA265ARCH2c4aCollection -Items $Attachments)
            Size=$Size
        }
    }
    function New-OPA265ARCH2c4aAttachment {
        param([byte[]]$Payload=[byte[]]@(0,1,2,255))
        $a=[pscustomobject]@{
            Type=1
            FileName='оригинал Ω.bin'
            Size=[int64]$Payload.Length
            Payload=[byte[]]$Payload
        }
        $a|Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$path)
            [IO.File]::WriteAllBytes($path,[byte[]]$this.Payload)
        }
        return $a
    }
}
Describe 'ARCH2c4a standalone core module dependency closure (no Outlook or PST)' {
    It 'loads Get-OPAInternetMessageId before invoking the real ARCH2b witness' {
        (Get-Command Get-OPAInternetMessageId -CommandType Function -ErrorAction Stop).Name | Should -BeExactly 'Get-OPAInternetMessageId'
    }
    It 'loads required Release-OPAComObject for MAPI PropertyAccessor cleanup' {
        (Get-Command Release-OPAComObject -CommandType Function -ErrorAction Stop).Name | Should -BeExactly 'Release-OPAComObject'
    }
    It 'can capture a complete real ARCH2b semantic witness from a Unicode MailItem mock' {
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail)
        $w.Schema | Should -BeExactly '2.6.5-ARCH2b.MailSemanticWitness.1'
        $w.AttachmentCount | Should -Be 0
        $w.BodyUtf16Length | Should -BeGreaterThan 0
        (Test-OPA265ARCH2bWitnessSchema -Witness $w) | Should -BeTrue
    }
    It 'integrates original MAPI internet message-id extraction in original source witness' {
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail)
        $expected=Get-OPA265ARCH2bTextSha256 -Text '<original-2020@example.test>'
        $w.InternetMessageIdSha256 | Should -BeExactly $expected
    }
    It 'hashes one original attachment through protected ARCH2c2 workspace with original SaveAsFile bytes' {
        $a=New-OPA265ARCH2c4aAttachment
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Attachments @($a))
        $w.AttachmentCount | Should -Be 1
        $w.Attachments[0].PayloadByteCount | Should -Be 4
        $w.Attachments[0].PayloadSha256 | Should -BeExactly '3d1f57c984978ef98a18378c8166c1cb8ede02c03eeb6aee7e2f121dfeee3e56'
    }
    It 'preserves full user content match when only provider MailItem.Size differs' {
        $left=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Size 1400)
        $right=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Size 1438)
        $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right
        $cmp.CriticalContentMatches | Should -BeTrue
        $cmp.ProviderSizeDifferenceIsNotAutomaticCorruption | Should -BeTrue
    }
    It 'fail-closes if body content differs after a mocked Move' {
        $left=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail)
        $right=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Body 'Изменено')
        $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right
        $cmp.CriticalContentMatches | Should -BeFalse
        $cmp.IssueCodes | Should -Contain 'DifferentBodySha256'
    }
    It 'fail-closes if attachment bytes differ although provider size matches' {
        $a=New-OPA265ARCH2c4aAttachment -Payload ([byte[]]@(0,1,2,255))
        $b=New-OPA265ARCH2c4aAttachment -Payload ([byte[]]@(0,1,2,254))
        $left=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Attachments @($a))
        $right=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Attachments @($b))
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right).IssueCodes | Should -Contain 'Attachment1DifferentPayloadSha256'
    }
    It 'fail-closes for unsupported embedded/linked attachment' {
        $a=New-OPA265ARCH2c4aAttachment
        $a.Type=5
        {Get-OPA265ARCH2bMailSemanticWitness -Mail (New-OPA265ARCH2c4aFakeMail -Attachments @($a))} | Should -Throw
    }
    It 'loads original runtime helpers in correct order without shadowing them' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2c4OneShotCore.ps1') -Raw -Encoding UTF8
        $p1=$src.IndexOf("../Runtime/ComManager.ps1")
        $p2=$src.IndexOf("ArchiveSelector.ps1")
        $p3=$src.IndexOf("ARCH2bSemanticWitness.ps1")
        ($p1 -gt 0 -and $p2 -gt $p1 -and $p3 -gt $p2) | Should -BeTrue
        $src | Should -Not -Match 'function Get-OPAInternetMessageId'
    }
}
