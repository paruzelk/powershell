#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Runtime/ComManager.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveSelector.ps1')
    . (Join-Path $script:root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveGrouping.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchivePlanner.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH2bSemanticWitness.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveVerifier.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH4Batch.ps1')
    function Get-OPAInternetMessageId {param([object]$Item) return [string]$Item.MessageId}
    function New-ARCH2bFakeCollection {
        param([object[]]$Items=@())
        $c=[pscustomobject]@{ Count=$Items.Count; Entries=@($Items) }
        $c | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$index) return $this.Entries[$index-1]
        }
        return $c
    }
    function New-ARCH2bFakeAttachment {
        param([string]$FileName='тест.bin',[byte[]]$Payload=[byte[]]@(0,1,2,255))
        $a=[pscustomobject]@{ Type=1; Size=[int64]$Payload.Length; FileName=$FileName; Content=$Payload }
        $a | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$file) [IO.File]::WriteAllBytes($file,[byte[]]$this.Content)
        }
        return $a
    }
    function New-ARCH2bFakeMail {
        param([object[]]$Attachments=@(),[string]$Subject='Тема Ω',
              [string]$Body='Текст письма',[string]$Html='<p>Текст письма</p>',
              [int64]$Size=1500)
        [pscustomobject]@{
            Class=43; Subject=$Subject; Body=$Body; HTMLBody=$Html
            SenderEmailAddress='sender@example.test'
            To='Кому <to@example.test>';CC='';BCC=''
            MessageId='<test@example.test>'
            ReceivedTime=[datetime]'2024-01-02T09:00:00Z'
            SentOn=[datetime]'2024-01-02T08:00:00Z'
            UnRead=$false;Importance=1;Sensitivity=0;Categories=''
            Size=$Size
            Recipients=(New-ARCH2bFakeCollection -Items @())
            Attachments=(New-ARCH2bFakeCollection -Items $Attachments)
        }
    }
    function New-ARCH5FakeCompoundAttachment {
        param([int]$Type=5,[byte]$LastByte=11)
        # Synthetic byte fixture exercises export identity, NOT actual MSG/OLE structure or Outlook.
        $bytes=New-Object byte[] 1024
        $head=[byte[]]@(0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1)
        [Array]::Copy($head,$bytes,8)
        $bytes[1023]=$LastByte
        $a=New-ARCH2bFakeAttachment -FileName 'nested.msg' -Payload $bytes
        $a.Type=$Type
        return $a
    }
    function New-ARCH5Folder {
        param([string]$Name,[string]$Id,[string]$Path,[int]$Count=1,[object[]]$Children=@())
        return [pscustomobject]@{Name=$Name;EntryID=$Id;FolderPath=$Path;DefaultItemType=0;Items=[pscustomobject]@{Count=$Count};Folders=$Children}
    }
}
Describe 'ARCH5 versioned full attachment witness' {
    It 'retains historical ARCH2b schema for old by-value witnesses' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH2bFakeAttachment))
        (Get-OPA265ARCH2bMailSemanticWitness -Mail $mail).Schema | Should -BeExactly '2.6.5-ARCH2b.MailSemanticWitness.1'
    }
    It 'extended witness retains exact ordinary file hash and original fingerprint verification' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH2bFakeAttachment))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness
        $w.Schema | Should -BeExactly '2.6.5-ARCH5.MailSemanticWitness.2'
        $w.Attachments[0].PayloadByteCount | Should -Be 4
        Test-OPAArchiveItemFingerprint -Item $mail -Expected ([pscustomobject]@{Subject=$mail.Subject;Sender=$mail.SenderEmailAddress;InternetMessageId=$mail.MessageId;SourceSemanticWitness=$w}) | Should -BeTrue
    }
    It 'requires explicit complex attachment consent before export' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment))
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness} | Should -Throw '*AttachmentTypeUnsupported: index=1 type=5*'
    }
    It 'exports the entire synthetic type 5 payload and verifies independent identical export' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness -AllowComplexAttachments
        $w.Attachments[0].Type | Should -Be 5
        $w.Attachments[0].PayloadByteCount | Should -Be 1024
        Test-OPAArchiveItemFingerprint -Item $mail -Expected ([pscustomobject]@{Subject=$mail.Subject;Sender=$mail.SenderEmailAddress;InternetMessageId=$mail.MessageId;SourceSemanticWitness=$w}) | Should -BeTrue
    }
    It 'accepts stable synthetic type 6 compound bytes with explicit consent' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment -Type 6))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness -AllowComplexAttachments
        $w.Attachments[0].Type | Should -Be 6
        Test-OPA265ARCH2bWitnessSchema -Witness $w | Should -BeTrue
    }
    It 'rejects a change to any byte of a complex attachment after Move' {
        $s=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment -LastByte 11))
        $d=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment -LastByte 12))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $s -ExtendedAttachmentWitness -AllowComplexAttachments
        Test-OPAArchiveItemFingerprint -Item $d -Expected ([pscustomobject]@{Subject=$s.Subject;Sender=$s.SenderEmailAddress;InternetMessageId=$s.MessageId;SourceSemanticWitness=$w}) | Should -BeFalse
    }
    It 'refuses an unstable compound export before Move' {
        $a=New-ARCH5FakeCompoundAttachment
        $a | Add-Member NoteProperty Counter 0
        $a | Add-Member -Force ScriptMethod SaveAsFile {
            param($file)
            $this.Counter++
            $this.Content[1023]=[byte]$this.Counter
            [IO.File]::WriteAllBytes($file,[byte[]]$this.Content)
        }
        {Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -ExtendedAttachmentWitness -AllowComplexAttachments} | Should -Throw '*AttachmentExportUnverified*'
    }
    It 'refuses incomplete or noncompound OLE exports even when consent is present' {
        $a=New-ARCH2bFakeAttachment -Payload (New-Object byte[] 1024)
        $a.Type=6
        {Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -ExtendedAttachmentWitness -AllowComplexAttachments} | Should -Throw '*AttachmentExportUnverified*'
    }
    It 'refuses by-reference attachments even with complex consent' {
        $a=New-ARCH2bFakeAttachment
        $a.Type=4
        {Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -ExtendedAttachmentWitness -AllowComplexAttachments} | Should -Throw '*AttachmentTypeUnsupported: index=1 type=4*'
    }
    It 'reports attachment size and limit separately from attachment type' {
        $a=New-ARCH2bFakeAttachment
        $a.Size=[long]1073741825
        {Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -ExtendedAttachmentWitness} | Should -Throw '*AttachmentSizeUnsupported: index=1 type=1 bytes=1073741825 limit=1073741824*'
    }
    It 'does not silently treat different witness policies as identical' {
        $mail=New-ARCH2bFakeMail
        $s=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        $d=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).CriticalContentMatches | Should -BeFalse
    }
    It 'rejects complex type in historical schema' {
        $mail=New-ARCH2bFakeMail -Attachments @((New-ARCH5FakeCompoundAttachment))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness -AllowComplexAttachments
        $w.Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
        Test-OPA265ARCH2bWitnessSchema -Witness $w | Should -BeFalse
    }
}
Describe 'ARCH5 actual folder eligibility and archive route checks' {
    It 'keeps eligible Sent and nested user folders, excluding entire Outbox subtree' {
        $nested=New-ARCH5Folder -Name 'Customer' -Id N -Path '\\POP3\Sent Items\Customer'
        $sent=New-ARCH5Folder -Name 'Sent Items' -Id S -Path '\\POP3\Sent Items' -Children @($nested)
        $deep=New-ARCH5Folder -Name '2020' -Id D -Path '\\POP3\Projects\2020'
        $user=New-ARCH5Folder -Name 'Projects' -Id P -Path '\\POP3\Projects' -Count 0 -Children @($deep)
        $bad=New-ARCH5Folder -Name 'Pending' -Id B -Path '\\POP3\Outbox\Pending'
        $outbox=New-ARCH5Folder -Name 'Outbox' -Id O -Path '\\POP3\Outbox' -Children @($bad)
        $root=New-ARCH5Folder -Name POP3 -Id ROOT -Path '\\POP3' -Count 0 -Children @($sent,$user,$outbox)
        $eligible=@(Get-OPAEligiblePop3MailFolders -RootFolder $root -WellKnownEntryIdMap @{S='SentMail';O='Outbox'})
        $eligible.FolderPath | Should -Contain '\\POP3\Sent Items'
        $eligible.FolderPath | Should -Contain '\\POP3\Sent Items\Customer'
        $eligible.FolderPath | Should -Contain '\\POP3\Projects\2020'
        $eligible.FolderPath | Should -Not -Contain '\\POP3\Outbox\Pending'
        $selected=@(Select-OPAARCH5SourceFolders -EligibleFolders $eligible -IncludeFolderPath @('\\POP3\Projects\2020','\\POP3\Sent Items'))
        $selected.Count | Should -Be 2
        {Select-OPAARCH5SourceFolders -EligibleFolders $eligible -IncludeFolderPath '\\POP3\Outbox\Pending'} | Should -Throw
    }
    It 'validates official SentOn year quarter even when ReceivedTime is newer' {
        $mail=[pscustomobject]@{SentOn=[datetime]'2020-10-12';ReceivedTime=[datetime]'2026-01-01'}
        $date=Get-OPAArchiveItemDate -Item $mail -PreferSentOn
        $date.Year | Should -Be 2020
        $src=Join-Path $TestDrive 'test.pst'
        {Assert-OPAARCH5Route -SourcePst $src -ArchiveDate $date -SourceFolderPath '\\POP3\Sent Items\Customer' -TargetFolderPath '\\Archive 2020\2020\Q4\Sent Items\Customer' -ArchivePst (Join-Path $TestDrive 'test.Archive-2020-02.pst') -Grouping YearQuarter} | Should -Not -Throw
    }
    It 'validates nested user path with annual grouping' {
        {Assert-OPAARCH5Route -SourcePst (Join-Path $TestDrive 'test.pst') -ArchiveDate ([datetime]'2020-02-03') -SourceFolderPath '\\POP3\Projects\Sub' -TargetFolderPath '\\Archive\2020\Projects\Sub' -ArchivePst (Join-Path $TestDrive 'test.Archive-2020.pst') -Grouping Year} | Should -Not -Throw
    }
    It 'rejects flattened target hierarchy' {
        {Assert-OPAARCH5Route -SourcePst (Join-Path $TestDrive 'test.pst') -ArchiveDate ([datetime]'2020-02-03') -SourceFolderPath '\\POP3\Projects\Sub' -TargetFolderPath '\\Archive\2020\Sub' -ArchivePst (Join-Path $TestDrive 'test.Archive-2020.pst') -Grouping Year} | Should -Throw '*ArchiveRouteMismatch*'
    }
    It 'rejects wrong quarter and wrong annual PST independently' {
        $args=@{SourcePst=(Join-Path $TestDrive 'test.pst');ArchiveDate=[datetime]'2020-04-01';SourceFolderPath='\\POP3\Inbox';Grouping='YearQuarter'}
        {Assert-OPAARCH5Route @args -TargetFolderPath '\\Archive\2020\Q1\Inbox' -ArchivePst (Join-Path $TestDrive 'test.Archive-2020.pst')} | Should -Throw
        {Assert-OPAARCH5Route @args -TargetFolderPath '\\Archive\2020\Q2\Inbox' -ArchivePst (Join-Path $TestDrive 'test.Archive-2021.pst')} | Should -Throw
    }
    It 'rejects archive PST outside the selected source directory' {
        {Assert-OPAARCH5Route -SourcePst (Join-Path $TestDrive 'test.pst') -ArchiveDate ([datetime]'2020-02-03') -SourceFolderPath '\\POP3\Inbox' -TargetFolderPath '\\Archive\2020\Inbox' -ArchivePst (Join-Path $TestDrive 'other\test.Archive-2020.pst') -Grouping Year} | Should -Throw
    }
}
Describe 'ARCH5 main CLI experimental guard' {
    It 'allows bounded explicit complex WhatIf without touching a PST' {
        $p=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst $p -ConfirmTestArchive -ConfirmComplexAttachments -Limit 1 -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path $p | Should -BeFalse
    }
    It 'rejects complex batch above ten before contacting Outlook' {
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'not-created.pst') -ConfirmTestArchive -ConfirmComplexAttachments -Limit 11 -WhatIf} | Should -Throw
    }
    It 'rejects folder filter in Resume to avoid incomplete source verification' {
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Resume -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'not-created.pst') -ConfirmTestArchive -IncludeFolderPath '\\POP3\Inbox' -WhatIf} | Should -Throw
    }
}

Describe 'ARCH5a recursive embedded message witness' {
    BeforeAll {
        function New-ARCH5aFakeEmbeddedParent {
            param([object[]]$ChildReads)
            $a=New-ARCH5FakeCompoundAttachment
            $a | Add-Member -NotePropertyName Counter -NotePropertyValue 0
            $a | Add-Member -Force -MemberType ScriptMethod -Name SaveAsFile -Value {
                param($file)
                $this.Counter++
                # Every export container differs; child MailItem is provided by
                # the fake OpenSharedItem reader, not by a real MSG parser.
                $this.Content[1023]=[byte]$this.Counter
                [IO.File]::WriteAllBytes($file,[byte[]]$this.Content)
            }
            $ns=[pscustomobject]@{Reads=$ChildReads;Count=0;Paths=@()}
            $ns | Add-Member -MemberType ScriptMethod -Name OpenSharedItem -Value {
                param($file)
                $this.Paths+= $file
                $i=$this.Count % $this.Reads.Count
                $this.Count++
                return $this.Reads[$i]
            }
            $mail=New-ARCH2bFakeMail -Attachments @($a)
            $mail | Add-Member -NotePropertyName Application -NotePropertyValue ([pscustomobject]@{Session=$ns})
            $mail | Add-Member -NotePropertyName CloseCount -NotePropertyValue 0
            $mail | Add-Member -MemberType ScriptMethod -Name Close -Value {param([int]$mode) if($mode -ne 1){throw 'Must discard'};$this.CloseCount++}
            return $mail
        }
        function New-ARCH5aFakeChild {
            param([string]$Body='embedded body',[int64]$Size=1000,[object[]]$Attachments=@())
            $m=New-ARCH2bFakeMail -Body $Body -Size $Size -Attachments $Attachments
            $m | Add-Member -NotePropertyName CloseCount -NotePropertyValue 0
            $m | Add-Member -MemberType ScriptMethod -Name Close -Value {param([int]$mode) if($mode -ne 1){throw 'Must discard'};$this.CloseCount++}
            return $m
        }
    }
    It 'accepts different exported containers with identical embedded content and discards private copies' {
        $c1=New-ARCH5aFakeChild -Size 1000
        $c2=New-ARCH5aFakeChild -Size 1100
        $mail=New-ARCH5aFakeEmbeddedParent -ChildReads @($c1,$c2)
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        $w.Schema | Should -BeExactly '2.6.5-ARCH5a.MailSemanticWitness.3'
        $w.Attachments[0].PayloadKind | Should -BeExactly 'EmbeddedMailSemanticSha256'
        $w.Attachments[0].PayloadByteCount | Should -Be 0
        $mail.Application.Session.Count | Should -Be 2
        $c1.CloseCount | Should -Be 1
        $c2.CloseCount | Should -Be 1
        foreach($p in $mail.Application.Session.Paths){Test-Path -LiteralPath $p | Should -BeFalse}
    }
    It 'rejects differing embedded body on independent pre-Move reads' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Body 'a'),(New-ARCH5aFakeChild -Body 'b'))
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments} | Should -Throw '*semantic content differs*'
    }
    It 'original verifier accepts same embedded message on destination without matching MSG file bytes' {
        $s=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Size 1000))
        $d=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Size 2000))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $s -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        Test-OPAArchiveItemFingerprint -Item $d -Expected ([pscustomobject]@{Subject=$s.Subject;Sender=$s.SenderEmailAddress;InternetMessageId=$s.MessageId;SourceSemanticWitness=$w}) | Should -BeTrue
    }
    It 'original verifier rejects changes to nested ordinary attachment bytes' {
        $s=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Attachments @((New-ARCH2bFakeAttachment -Payload ([byte[]]@(1,2,3))))))
        $d=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Attachments @((New-ARCH2bFakeAttachment -Payload ([byte[]]@(1,2,4))))))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $s -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        Test-OPAArchiveItemFingerprint -Item $d -Expected ([pscustomobject]@{Subject=$s.Subject;Sender=$s.SenderEmailAddress;InternetMessageId=$s.MessageId;SourceSemanticWitness=$w}) | Should -BeFalse
    }
    It 'recurses through two levels and rejects a deeper changed payload' {
        $sInner=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Body 'deep original'))
        $dInner=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild -Body 'deep changed'))
        $s=New-ARCH5aFakeEmbeddedParent -ChildReads @($sInner)
        $d=New-ARCH5aFakeEmbeddedParent -ChildReads @($dInner)
        $a=Get-OPA265ARCH2bMailSemanticWitness -Mail $s -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        $b=Get-OPA265ARCH2bMailSemanticWitness -Mail $d -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $a -Destination $b).CriticalContentMatches | Should -BeFalse
    }
    It 'refuses embedded non-MailItem instead of treating it as empty' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @([pscustomobject]@{Class=26})
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments} | Should -Throw '*not a readable MailItem*'
    }
    It 'enforces depth bound before opening deeper MSG' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild))
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments -EmbeddedDepth 4} | Should -Throw '*depth limit*'
        $m.Application.Session.Count | Should -Be 0
    }
    It 'enforces shared read budget before opening MSG' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild))
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments -EmbeddedBudget @{Remaining=0}} | Should -Throw '*read budget*'
        $m.Application.Session.Count | Should -Be 0
    }
    It 'requires the exact version 3 payload-kind marker' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild))
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments
        $w.Attachments[0].PayloadKind='Unverified'
        Test-OPA265ARCH2bWitnessSchema -Witness $w | Should -BeFalse
    }
    It 'retains explicit consent requirement and does not open MSG by default' {
        $m=New-ARCH5aFakeEmbeddedParent -ChildReads @((New-ARCH5aFakeChild))
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $m -ExtendedAttachmentWitness -RecursiveEmbeddedWitness} | Should -Throw '*AttachmentTypeUnsupported*'
        $m.Application.Session.Count | Should -Be 0
    }
}

Describe 'ARCH5b private MSG cleanup and error preservation' {
    It 'deletes only the specifically created private MSG export' {
        $w=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $TestDrive
        try{
            $p=Join-Path $w.WorkspacePath ('OPA-ARCH5a-'+[guid]::NewGuid().ToString('N')+'.msg')
            [IO.File]::WriteAllBytes($p,[byte[]]@(1,2,3))
            Remove-OPAARCH5bPrivateMsgExport -Path $p -Workspace $w.WorkspacePath -Attempts 1
            Test-Path -LiteralPath $p | Should -BeFalse
            Test-Path -LiteralPath $w.LeasePath | Should -BeTrue
        }finally{Close-OPA265ARCH2c2PrivateWorkspace -Workspace $w}
    }
    It 'refuses a foreign file name in a private workspace' {
        $w=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $TestDrive
        $p=Join-Path $w.WorkspacePath 'foreign.msg'
        try{
            [IO.File]::WriteAllBytes($p,[byte[]]@(1))
            {Remove-OPAARCH5bPrivateMsgExport -Path $p -Workspace $w.WorkspacePath -Attempts 1} | Should -Throw '*path mismatch*'
            Test-Path -LiteralPath $p | Should -BeTrue
        }finally{
            [IO.File]::Delete($p)
            Close-OPA265ARCH2c2PrivateWorkspace -Workspace $w
        }
    }
    It 'retains a held MSG rather than deleting an unrelated export' {
        $w=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $TestDrive
        $p=Join-Path $w.WorkspacePath ('OPA-ARCH5a-'+[guid]::NewGuid().ToString('N')+'.msg')
        $h=$null
        try{
            $h=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            {Remove-OPAARCH5bPrivateMsgExport -Path $p -Workspace $w.WorkspacePath -Attempts 2 -DelayMilliseconds 0} | Should -Throw
            Test-Path -LiteralPath $p | Should -BeTrue
        }finally{
            if($null -ne $h){$h.Dispose()}
            Remove-OPAARCH5bPrivateMsgExport -Path $p -Workspace $w.WorkspacePath -Attempts 1
            Close-OPA265ARCH2c2PrivateWorkspace -Workspace $w
        }
    }
    It 'retains original capture exception when workspace cleanup fails too' {
        $a=New-ARCH2bFakeAttachment
        $a | Add-Member -Force -MemberType ScriptMethod -Name SaveAsFile -Value {param($file) throw 'original-capture-error'}
        $mail=New-ARCH2bFakeMail -Attachments @($a)
        Mock Close-OPA265ARCH2c2PrivateWorkspace {
            $Workspace.LeaseStream.Dispose()
            [IO.File]::Delete($Workspace.LeasePath)
            [IO.Directory]::Delete($Workspace.WorkspacePath,$false)
            throw 'secondary-cleanup-error'
        }
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -ExtendedAttachmentWitness} | Should -Throw '*AttachmentCleanupFailed*capture=*original-capture-error*workspace cleanup=*secondary-cleanup-error*'
    }
}
