#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3vRealTenFullWitness.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3sFakeOutlookTenObjects.ps1')
    $script:runId='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
    $script:source='C:\SYNTHETIC-ARCH3v-TEST-ONLY\info@stios.ru.pst'
    $script:target='C:\SYNTHETIC-ARCH3v-TEST-ONLY\info@stios.ru.Archive-2020-03.pst'
    $script:parent=[pscustomobject]@{EntryID=('A'*32);StoreID='ARCH3v-SYNTH-STORE'}
    $previewRows=New-Object 'System.Collections.Generic.List[object]'
    $witnessRows=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le 10;$i++){
        $id=('{0:X16}' -f $i)
        $mail=New-OPA265ARCH3sFakeMail -Number $i -EntryId $id -Parent $script:parent
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        $date=[datetime]$mail.ReceivedTime
        $contract=(Get-OPA265ARCH3bDigest -Parts @('ARCH3v SYNTHETIC',$script:runId,$id,[string]$i))
        [void]$previewRows.Add([pscustomobject]@{
            SourceEntryId=$id;ArchiveDate=$date
            OriginalOperationId=('ARCH3b-'+$contract)
            OriginalContractSha256=$contract
            TargetPstPreview=$script:target
            TargetFolderPath='2020\Входящие'
            AttachmentCount=[int]$w.AttachmentCount
            SubjectSha256=[string]$w.SubjectSha256
        })
        [void]$witnessRows.Add([pscustomobject][ordered]@{
            Ordinal=$i
            SourceEntryId=$id
            OriginalOperationId=('ARCH3b-'+$contract)
            OriginalContractSha256=$contract
            TargetFolderPath='2020\Входящие'
            TargetPstPreview=$script:target
            ArchiveDateLocalTicks=[long]$date.Ticks
            ArchiveDateUtcTicks=[long]$date.ToUniversalTime().Ticks
            AttachmentCount=[int]$w.AttachmentCount
            SubjectSha256=[string]$w.SubjectSha256
            FullOriginalWitnessSha256=(Get-OPA265ARCH3dOriginalWitnessHash -Witness $w)
            OriginalWitness=$w
        })
    }
    $script:preview=[pscustomobject]@{
        Schema='2.6.5-ARCH3u.RealBatchTenPreview.1'
        RunId=$script:runId
        SourcePst=$script:source
        PreviewSha256=('a'*64)
        SourceStoreIdSha256=('b'*64)
        OriginalIndexSha256=('c'*64)
        SourcePstLengthBytes=[long]7735903232
        SelectedYear=2020
        SelectedArchivePart=3
        TargetPstPreview=$script:target
        BatchSize=10
        Rows=@($previewRows.ToArray())
        WriterPermit=$false
        ProductionReady=$false
    }
    $script:bundle=New-OPA265ARCH3vEnvelopeFromPreview -Preview $script:preview -WitnessRows @($witnessRows.ToArray())
}
Describe 'ARCH3v ten REAL TEST PST original full ARCH2b witnesses and protected evidence-only Seal' {
    BeforeEach {
        # Deep clone so each fault test cannot contaminate the baseline.
        $script:record=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $script:bundle.Envelope -Depth 30 -Compress)
    }
    It 'builds exactly ten ORIGINAL full semantic records and valid canonical AuditSha256' {
        $script:bundle.AuditSha256 | Should -Match '^[a-f0-9]{64}$'
        $script:bundle.Envelope.Rows.Count | Should -Be 10
        (Get-OPA265ARCH3vAuditDigest -Envelope $script:record) | Should -BeExactly $script:bundle.AuditSha256
    }
    It 'keeps original Body, HTML, recipients and attachment payload byte SHA for every selected MailItem' {
        foreach($r in $script:record.Rows){
            $r.OriginalWitness.BodySha256 | Should -Match '^[a-f0-9]{64}$'
            $r.OriginalWitness.HtmlBodySha256 | Should -Match '^[a-f0-9]{64}$'
            $r.OriginalWitness.OrderedRecipientDigestSha256 | Should -Match '^[a-f0-9]{64}$'
            foreach($a in $r.OriginalWitness.Attachments){
                $a.PayloadSha256 | Should -Match '^[a-f0-9]{64}$'
                [long]$a.PayloadByteCount | Should -BeGreaterThan 0
            }
        }
    }
    It 'rejects changed original Body SHA after source witness was externally hashed' {
        $script:record.Rows[4].OriginalWitness.BodySha256='d'*64
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects changed actual attachment payload SHA' {
        $script:record.Rows[4].OriginalWitness.Attachments[0].PayloadSha256='e'*64
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects changed original HTML SHA' {
        $script:record.Rows[1].OriginalWitness.HtmlBodySha256='e'*64
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects changed original recipient digest' {
        $script:record.Rows[1].OriginalWitness.OrderedRecipientDigestSha256='e'*64
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects changed original user UnRead state digest' {
        $script:record.Rows[1].OriginalWitness.UnRead=(-not [bool]$script:record.Rows[1].OriginalWitness.UnRead)
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects mismatched attachment count even with original payload unchanged' {
        $script:record.Rows[4].AttachmentCount=1
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects mismatched subject hash' {
        $script:record.Rows[0].SubjectSha256='f'*64
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects repeated original source EntryID in an otherwise full ten bundle' {
        $script:record.Rows[4].SourceEntryId=[string]$script:record.Rows[0].SourceEntryId
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects reused operation identity even for different source EntryIDs' {
        $script:record.Rows[4].OriginalContractSha256=[string]$script:record.Rows[0].OriginalContractSha256
        $script:record.Rows[4].OriginalOperationId=[string]$script:record.Rows[0].OriginalOperationId
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects missing original attachment-inclusive witness' {
        $script:record.Rows[0].OriginalWitness=$null
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects missing tenth source MailItem' {
        $script:record.Rows=@($script:record.Rows | Select-Object -First 9)
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects wrong archive folder in only one message' {
        $script:record.Rows[0].TargetFolderPath='2020\Wrong'
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects wrong Year/Part even if all source MailItems still match' {
        $script:record.ArchivePart=2
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects existing Part2 target instead of operator selected Part3' {
        $script:record.TargetPstPreview='C:\SYNTHETIC-ARCH3v-TEST-ONLY\info@stios.ru.Archive-2020-02.pst'
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects any original production writer flag' {
        $script:record.WriterPermit=$true
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects malformed pinned original index SHA' {
        $script:record.OriginalIndexSha256='INVALID'
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects source archive date versus original ReceivedUtcTicks drift' {
        $script:record.Rows[0].ArchiveDateUtcTicks++
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'rejects total attachment summary drift' {
        $script:record.TotalAttachmentCount++
        {Get-OPA265ARCH3vAuditDigest -Envelope $script:record} | Should -Throw
    }
    It 'cannot seal a witness not belonging to original ARCH3u candidate contract' {
        $script:record.Rows[4].OriginalContractSha256='f'*64
        {New-OPA265ARCH3vEnvelopeFromPreview -Preview $script:preview -WitnessRows @($script:record.Rows)} | Should -Throw
    }
    It 'audit digest changes if independently pinned original index changes' {
        $first=Get-OPA265ARCH3vAuditDigest -Envelope $script:record
        $script:record.OriginalIndexSha256='d'*64
        (Get-OPA265ARCH3vAuditDigest -Envelope $script:record) | Should -Not -BeExactly $first
    }
    It 'Plan performs no Outlook access or PST file access' {
        $plan=Invoke-OPA265ARCH3vRealTenFullWitness -Mode Plan -RunId $script:runId -SourcePst $script:source
        $plan.Status | Should -BeExactly 'ExactRealTenFullOriginalWitnessPlanNoOutlookNoWrites'
        $plan.OutlookContacted | Should -BeFalse
        $plan.WriterPermit | Should -BeFalse
    }
    It 'Seal WhatIf writes no evidence and contacts no Outlook' {
        $path=Join-Path $TestDrive 'info@stios.ru.pst'
        [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
        $run=[guid]::NewGuid().ToString('D')
        $pins=@{
            Mode='Seal';RunId=$run;SourcePst=$path
            ExpectedPreviewSha256=('a'*64);ExpectedSourceStoreIdSha256=('b'*64)
            ExpectedOriginalIndexSha256=('c'*64);ExpectedSourcePstLengthBytes=3
            ExpectedAuditSha256=('d'*64);ConfirmEvidenceWrite=$true
        }
        $what=Invoke-OPA265ARCH3vRealTenFullWitness @pins -WhatIf
        $what.Status | Should -BeExactly 'EvidenceSealWhatIfNoWrites'
        [IO.Directory]::Exists([string](Get-OPA265ARCH3vEvidenceLayout -RunId $run).Root) | Should -BeFalse
    }
    It 'requires independently observed external audit SHA and explicit evidence confirmation' {
        $path=Join-Path $TestDrive 'info@stios.ru.pst'
        [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
        $pins=@{
            Mode='Seal';RunId=([guid]::NewGuid().ToString('D'));SourcePst=$path
            ExpectedPreviewSha256=('a'*64);ExpectedSourceStoreIdSha256=('b'*64)
            ExpectedOriginalIndexSha256=('c'*64);ExpectedSourcePstLengthBytes=3
            ExpectedAuditSha256=('d'*64);Confirm=$false
        }
        {Invoke-OPA265ARCH3vRealTenFullWitness @pins} | Should -Throw
    }
    It 'Review rejects writer and source selectors instead of contacting Outlook' {
        $args=@{Mode='Review';RunId=$script:runId;SealSha256=('a'*64);SourcePst=$script:source;Confirm=$false}
        {Invoke-OPA265ARCH3vRealTenFullWitness @args} | Should -Throw
    }
    It 'private directory and immutable CreateNew original writer read back all ten semantic records' {
        $run=[guid]::NewGuid().ToString('D')
        $layout=Get-OPA265ARCH3vEvidenceLayout -RunId $run
        $script:record.RunId=$run
        $script:record | Add-Member -NotePropertyName AuditSha256 -NotePropertyValue (Get-OPA265ARCH3vAuditDigest -Envelope $script:record)
        $script:record | Add-Member -NotePropertyName FullOriginalSemanticWitnessesCaptured -NotePropertyValue $true
        $script:record | Add-Member -NotePropertyName SealedEvidenceWritten -NotePropertyValue $true
        try {
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
            $sha=Write-OPA265ARCH3cJsonOnce -Path $layout.WitnessPath -Record $script:record
            $read=Test-OPA265ARCH3vFullTenReadback -Layout $layout -SealSha256 $sha
            $read.Status | Should -BeExactly 'TenOriginalFullSemanticsSealedIndependentlyReadBackNoMove'
            $read.FullOriginalWitnessesVerified | Should -Be 10
            $read.WriterPermit | Should -BeFalse
            {Write-OPA265ARCH3cJsonOnce -Path $layout.WitnessPath -Record $script:record} | Should -Throw
        }finally {
            if([IO.Directory]::Exists([string]$layout.Root)){
                Remove-Item -LiteralPath $layout.Root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    It 'fails independent Review when byte-sealed original evidence is tampered' {
        $run=[guid]::NewGuid().ToString('D')
        $layout=Get-OPA265ARCH3vEvidenceLayout -RunId $run
        $script:record.RunId=$run
        $script:record | Add-Member -NotePropertyName AuditSha256 -NotePropertyValue (Get-OPA265ARCH3vAuditDigest -Envelope $script:record)
        $script:record | Add-Member -NotePropertyName FullOriginalSemanticWitnessesCaptured -NotePropertyValue $true
        $script:record | Add-Member -NotePropertyName SealedEvidenceWritten -NotePropertyValue $true
        try {
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
            $sha=Write-OPA265ARCH3cJsonOnce -Path $layout.WitnessPath -Record $script:record
            [IO.File]::AppendAllText($layout.WitnessPath,'TAMPER')
            {Test-OPA265ARCH3vFullTenReadback -Layout $layout -SealSha256 $sha} | Should -Throw
        }finally{
            if([IO.Directory]::Exists([string]$layout.Root)){Remove-Item -LiteralPath $layout.Root -Recurse -Force -ErrorAction SilentlyContinue}
        }
    }
    It 'no existing evidence RunId can be used to reset an externally witnessed baseline' {
        $path=Join-Path $TestDrive 'info@stios.ru.pst'
        [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
        $run=[guid]::NewGuid().ToString('D')
        $layout=Get-OPA265ARCH3vEvidenceLayout -RunId $run
        try{
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
            $args=@{
                Mode='Seal';RunId=$run;SourcePst=$path
                ExpectedPreviewSha256=('a'*64);ExpectedSourceStoreIdSha256=('b'*64)
                ExpectedOriginalIndexSha256=('c'*64);ExpectedSourcePstLengthBytes=3
                ExpectedAuditSha256=('d'*64);ConfirmEvidenceWrite=$true;Confirm=$false
            }
            {Invoke-OPA265ARCH3vRealTenFullWitness @args} | Should -Throw
        }finally{
            if([IO.Directory]::Exists([string]$layout.Root)){Remove-Item -LiteralPath $layout.Root -Recurse -Force -ErrorAction SilentlyContinue}
        }
    }
    It 'UTF-8 BOM required and new files contain no real Move or PST writer surface' {
        foreach($f in @('Invoke-ARCH3v.ps1','Core/Archive/ARCH3vRealTenFullWitness.ps1')){
            $full=Join-Path $script:root $f
            $bytes=[IO.File]::ReadAllBytes($full)
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
            $content=[IO.File]::ReadAllText($full)
            $content | Should -Not -Match '\.Move\s*\('
            $content | Should -Not -Match '\.AddStoreEx\s*\('
            $content | Should -Not -Match 'Write-OPAOperationJournalEvent\s'
            $content | Should -Not -Match 'Add-OPADuplicateEntry\s'
        }
    }
}
