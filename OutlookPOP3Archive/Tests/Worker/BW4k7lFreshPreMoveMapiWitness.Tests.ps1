#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7lFreshPreMoveMapiWitness265.ps1')
    function New-BW4k7lFixture {
        $id='1d0d4951-7c65-4a71-88b4-e96da519bc1e'
        $keyF='http://schemas.microsoft.com/mapi/proptag/0x0E070003'
        $keyS='http://schemas.microsoft.com/mapi/proptag/0x0E170003'
        $keyA='http://schemas.microsoft.com/mapi/proptag/0x0E1B000B'
        $map=@{}
        $map[$keyF]=[int]65555
        $map[$keyS]=[int]0
        $map[$keyA]=$true
        $map['http://schemas.microsoft.com/mapi/proptag/0x1035001F']='<bw4k7l-1d0d4951@example.test>'
        $map['http://schemas.microsoft.com/mapi/proptag/0x300B0102']=[byte[]]@(1,2,3,4,5)
        $pa=[pscustomobject]@{Map=$map}
        $pa | Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
            param($tag)
            if(-not $this.Map.ContainsKey($tag)){
                throw (New-Object System.Runtime.InteropServices.COMException('missing',-2147221233))
            }
            return $this.Map[$tag]
        }
        $attachment=[pscustomobject]@{Type=1;FileName='fixture-1k.bin';Seed=0}
        $attachment | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param($path)
            [byte[]]$data=New-Object byte[] 1024
            for($i=0;$i -lt 1024;$i++){$data[$i]=[byte](($i+[int]$this.Seed)%251)}
            [IO.File]::WriteAllBytes([string]$path,$data)
        }
        $att=[pscustomobject]@{Count=1;First=$attachment}
        $att | Add-Member -MemberType ScriptMethod -Name Item -Value {param($index)if($index -ne 1){throw 'index'};return $this.First}
        $rc=[pscustomobject]@{Count=1;First=[pscustomobject]@{Type=1;Name='Synthetic To';Address='to@example.test'}}
        $rc | Add-Member -MemberType ScriptMethod -Name Item -Value {param($index)if($index -ne 1){throw 'index'};return $this.First}
        $entry='A'*48;$folder='B'*48;$store='synthetic-store'
        $mail=[pscustomobject]@{
            Class=43;EntryID=$entry;Parent=[pscustomobject]@{EntryID=$folder;StoreID=$store}
            Subject=('OPA265-BW4k7l-'+$id)
            Body=('OPA265-BW4k7l disposable fixture '+$id+' - independent experiment')
            HTMLBody=('<html>OPA265-BW4k7l disposable fixture '+$id+'</html>')
            Recipients=$rc;Attachments=$att;PropertyAccessor=$pa
            UnRead=$false;SenderEmailAddress='sender@example.test'
            ReceivedTime=[datetime]'2026-11-03T09:00:00Z'
            SentOn=[datetime]'2026-11-03T08:59:00Z'
            Size=[long]9000
        }
        return [pscustomobject]@{
            Mail=$mail;Id=$id;Entry=$entry;Folder=$folder;Store=$store
            Pa=$pa;Attachment=$attachment;FlagsTag=$keyF;StatusTag=$keyS;AttachTag=$keyA
        }
    }
    function Get-BW4k7lWitness {
        param($F)
        $p=@{
            Mail=$F.Mail;FixtureId=$F.Id;ExpectedEntryId=$F.Entry
            ExpectedFolderId=$F.Folder;ExpectedStoreId=$F.Store
        }
        Get-OPA265BW4k7lFreshMailWitness @p
    }
}
Describe 'BW4k7l new synthetic 1K source message pre-Move witness' {
    It 'accepts new GUID and blocks historical Attachment1K GUID' {
        (Assert-OPA265BW4k7lFixtureId -FixtureId '1d0d4951-7c65-4a71-88b4-e96da519bc1e') | Should -BeTrue
        {Assert-OPA265BW4k7lFixtureId -FixtureId '87e72fd0-9e77-4098-a403-cbe99870b9e7'} | Should -Throw
    }
    It 'rejects uppercase and invalid fixture GUID' {
        {Assert-OPA265BW4k7lFixtureId -FixtureId '1D0D4951-7c65-4a71-88b4-e96da519bc1e'} | Should -Throw
        {Assert-OPA265BW4k7lFixtureId -FixtureId 'invalid'} | Should -Throw
    }
    It 'captures original flags/status/attach separately, including unknown 0x10000' {
        $w=Get-BW4k7lWitness (New-BW4k7lFixture)
        $w.Schema | Should -BeExactly '2.6.5-BW4k7l.FreshPreMoveMapiWitness.1'
        $w.RawPrMessageFlags | Should -Be 65555
        $w.RawPrMessageFlagsHex | Should -BeExactly '0x00010013'
        $w.RawFlag0x00010000BeforeMove | Should -BeTrue
        $w.PrMessageStatusAvailable | Should -BeTrue
        $w.PrMessageStatus | Should -Be 0
        $w.PrHasAttach | Should -BeTrue
        $w.AttachmentByteLength | Should -Be 1024
        $w.AttachmentBytesSha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'independent two reads are fully stable' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        $b=Get-BW4k7lWitness $f
        (Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b) | Should -BeTrue
    }
    It 'never asserts Move, writer permission or production' {
        $w=Get-BW4k7lWitness (New-BW4k7lFixture)
        $w.BeforeMove | Should -BeTrue
        $w.OutlookMoveExecuted | Should -BeFalse
        $w.WriterPermit | Should -BeFalse
        $w.ProductionReady | Should -BeFalse
        $w.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'records original unambiguous InternetMessageId and SearchKey SHA' {
        $w=Get-BW4k7lWitness (New-BW4k7lFixture)
        $w.InternetMessageId | Should -BeExactly '<bw4k7l-1d0d4951@example.test>'
        $w.InternetMessageIdSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.SearchKeySha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'captures original sender, UTC timestamps and diagnostic size' {
        $w=Get-BW4k7lWitness (New-BW4k7lFixture)
        $w.SenderSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.ReceivedUtcTicks | Should -BeGreaterThan 0
        $w.SentUtcTicks | Should -BeGreaterThan 0
        $w.MessageSizeDiagnostic | Should -Be 9000
    }
    It 'missing optional PR_MESSAGE_STATUS is not silently zero' {
        $f=New-BW4k7lFixture
        [void]$f.Pa.Map.Remove($f.StatusTag)
        $w=Get-BW4k7lWitness $f
        $w.PrMessageStatusAvailable | Should -BeFalse
        $null -eq $w.PrMessageStatus | Should -BeTrue
    }
    It 'wrong PR_MESSAGE_STATUS type fails closed' {
        $f=New-BW4k7lFixture
        $f.Pa.Map[$f.StatusTag]='invalid'
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'missing PR_MESSAGE_FLAGS fails closed' {
        $f=New-BW4k7lFixture
        [void]$f.Pa.Map.Remove($f.FlagsTag)
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'missing PR_HASATTACH fails closed' {
        $f=New-BW4k7lFixture
        [void]$f.Pa.Map.Remove($f.AttachTag)
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'HASATTACH false fails closed' {
        $f=New-BW4k7lFixture
        $f.Pa.Map[$f.AttachTag]=$false
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'read flag contradicting UnRead fails closed' {
        $f=New-BW4k7lFixture;$f.Mail.UnRead=$true
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'missing HASATTACH bit fails closed' {
        $f=New-BW4k7lFixture;$f.Pa.Map[$f.FlagsTag]=[int]65539
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'by-reference attachment fails closed' {
        $f=New-BW4k7lFixture;$f.Attachment.Type=4
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'unexpected attachment bytes length fails closed' {
        $f=New-BW4k7lFixture
        $f.Attachment | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Force -Value {
            param($path)
            [IO.File]::WriteAllBytes([string]$path,(New-Object byte[] 100))
        }
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'attachment byte change is detected by two-witness validator' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        $f.Attachment.Seed=3
        $b=Get-BW4k7lWitness $f
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw '*differed*'
    }
    It 'different message body changes semantic witness' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        $f.Mail.Body+=' changed'
        $b=Get-BW4k7lWitness $f
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw
    }
    It 'changed status value is detected' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        $f.Pa.Map[$f.StatusTag]=[int]65536
        $b=Get-BW4k7lWitness $f
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw
    }
    It 'missing status in only one read is detected' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        [void]$f.Pa.Map.Remove($f.StatusTag)
        $b=Get-BW4k7lWitness $f
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw
    }
    It 'recipient address drift changes digest' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f
        $f.Mail.Recipients.First.Address='different@example.test'
        $b=Get-BW4k7lWitness $f
        $a.RecipientDigestSha256 | Should -Not -BeExactly $b.RecipientDigestSha256
    }
    It 'missing recipient address fails closed' {
        $f=New-BW4k7lFixture;$f.Mail.Recipients.First.Address=''
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'missing InternetMessageId fails closed' {
        $f=New-BW4k7lFixture
        $f.Pa.Map['http://schemas.microsoft.com/mapi/proptag/0x1035001F']=''
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'missing PR_SEARCH_KEY fails closed' {
        $f=New-BW4k7lFixture
        $f.Pa.Map['http://schemas.microsoft.com/mapi/proptag/0x300B0102']=[byte[]]@()
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'wrong disposable fixture subject fails closed' {
        $f=New-BW4k7lFixture;$f.Mail.Subject='unrelated'
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'wrong EntryID fails closed' {
        $f=New-BW4k7lFixture;$f.Mail.EntryID='C'*48
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'wrong source store fails closed' {
        $f=New-BW4k7lFixture;$f.Mail.Parent.StoreID='wrong'
        {Get-BW4k7lWitness $f} | Should -Throw
    }
    It 'stable validator refuses forged writer permission' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f;$b=Get-BW4k7lWitness $f
        $b.WriterPermit=$true
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw
    }
    It 'stable validator refuses incomplete schema' {
        $f=New-BW4k7lFixture
        $a=Get-BW4k7lWitness $f;$b=Get-BW4k7lWitness $f
        [void]$b.PSObject.Properties.Remove('SourceEntryId')
        {Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b} | Should -Throw
    }
    It 'string SHA256 matches reference' {
        (Get-OPA265BW4k7lStringSha -Value 'abc') | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
    It 'writes durable immutable evidence once, then blocks second attempt' {
        $old=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=$TestDrive
            $f=New-BW4k7lFixture;$w=Get-BW4k7lWitness $f
            $rec=[pscustomobject]@{
                Schema='2.6.5-BW4k7l.ImmutablePreMoveEvidence.1';FixtureId=$f.Id;SourceWitness=$w
                OutlookMoveExecuted=$false;WriterPermit=$false;ProductionReady=$false;AutomaticRetryAllowed=$false
            }
            $result=Write-OPA265BW4k7lEvidenceOnce -Record $rec
            $result.CreatedOnce | Should -BeTrue
            (Get-FileHash -LiteralPath $result.EvidencePath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $result.EvidenceSha256
            {Write-OPA265BW4k7lEvidenceOnce -Record $rec} | Should -Throw '*already exists*'
        }finally{$env:LOCALAPPDATA=$old}
    }
    It 'never serializes forged writer permit' {
        $f=New-BW4k7lFixture
        $rec=[pscustomobject]@{
            Schema='2.6.5-BW4k7l.ImmutablePreMoveEvidence.1';FixtureId=$f.Id
            OutlookMoveExecuted=$false;WriterPermit=$true;ProductionReady=$false
        }
        {Write-OPA265BW4k7lEvidenceOnce -Record $rec} | Should -Throw
    }
    It 'controller strictly guards Capture approval and selected POP3 Inbox' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7lFreshPreMoveReview.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $source | Should -Match "ValidateSet\('Review','Capture'\)"
        $source | Should -Match 'ConfirmImmutableCapture'
        $source | Should -Match 'Get-OPA265BW4cPop3Store'
        $source | Should -Match 'GetDefaultFolder\(6\)'
        $source | Should -Match 'Selection\.Count -ne 1'
        $source | Should -Match 'Assert-OPA265BW4k7lStableFreshWitness'
        $source | Should -Match 'Write-OPA265BW4k7lEvidenceOnce'
        $source | Should -Match 'ShouldProcess'
        $source | Should -Not -Match '(?i)\$mail\.(Move|Save|Delete|Send)\s*\('
        $source | Should -Not -Match '\.SetProperty\s*\('
    }
    It 'controller preserves original historical Claim and production blocks' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7lFreshPreMoveReview.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $source | Should -Match '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        $source | Should -Not -Match 'Write-OPA265BW4k7gClaimOnce|ReconciledJournal|SourceMove'
        $source | Should -Match 'ProductionReady=\$false'
        $source | Should -Match 'WriterPermit=\$false'
    }
}
