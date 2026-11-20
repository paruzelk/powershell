#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3wTenOriginalIntents.ps1')
    function New-ARCH3wFixture {
        $id='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
        $source='C:\SYNTHETIC-ARCH3w-TEST\info@stios.ru.pst'
        $target='C:\SYNTHETIC-ARCH3w-TEST\info@stios.ru.Archive-2020-03.pst'
        $rows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $ch=('{0:X16}' -f $i)
            $op=(Get-OPA265ARCH3bDigest -Parts @('ARCH3w-FAKE',$id,$ch))
            $num=if($i -eq 10){5}elseif($i -le 4){1}elseif($i -le 6){2}else{0}
            if($i -eq 1){$num=0}
            [void]$rows.Add([pscustomobject][ordered]@{
                Ordinal=$i;SourceEntryId=$ch
                OriginalOperationId=('ARCH3b-'+$op)
                OriginalContractSha256=$op
                FullOriginalWitnessSha256=(Get-OPA265ARCH3bDigest -Parts @('FAKE FULL SHA',$ch))
                TargetFolderPath='2020\Входящие';AttachmentCount=$num
            })
        }
        # The production stage is anchored to exact real 12 attachments;
        # adjust the synthetic rows so the total is also 12.
        $rows[1].AttachmentCount=1
        $rows[2].AttachmentCount=1
        $rows[3].AttachmentCount=1
        $rows[4].AttachmentCount=2
        $rows[5].AttachmentCount=2
        $rows[6].AttachmentCount=0
        $rows[7].AttachmentCount=0
        $rows[8].AttachmentCount=0
        $rows[9].AttachmentCount=5
        $seal=[pscustomobject][ordered]@{
            RunId=$id;SourcePst=$source
            SealSha256=('d'*64)
            AuditSha256=('a'*64);PreviewSha256=('b'*64)
            OriginalIndexSha256=('c'*64);SourceStoreIdSha256=('e'*64)
            SourcePstLengthBytes=[long]7735903232
            TargetPstPreview=$target;BatchSize=10;TotalAttachmentCount=12
            Rows=@($rows.ToArray())
        }
        $parts=@(
            [pscustomobject][ordered]@{Part=1;Path='C:\SYNTHETIC-ARCH3w-TEST\info@stios.ru.Archive-2020.pst';LengthBytes=[long]250000;Sha256=('1'*64)}
            [pscustomobject][ordered]@{Part=2;Path='C:\SYNTHETIC-ARCH3w-TEST\info@stios.ru.Archive-2020-02.pst';LengthBytes=[long]275000;Sha256=('2'*64)}
        )
        return [pscustomobject]@{Seal=$seal;Parts=$parts;RawStoreId='ARCH3w-FAKE-POP3-STORE'}
    }
    $script:fixture=New-ARCH3wFixture
    function New-ARCH3wTestManifest {
        $m=New-OPA265ARCH3wManifest -Seal $script:fixture.Seal -SealSha256 ('d'*64) -ExistingArchiveParts $script:fixture.Parts
        return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $m -Depth 30 -Compress))
    }
    function New-ARCH3wOriginalJournal {
        param([Parameter(Mandatory=$true)][object]$Layout,
              [Parameter(Mandatory=$true)][object]$Manifest,
              [int]$Number=10)
        $path=[string]$Layout.JournalPath
        for($i=0;$i -lt $Number;$i++){
            $row=$Manifest.Rows[$i]
            [void](Write-OPAOperationJournalEvent -Path $path -TransactionId ('ARCH3w-'+[string]$Manifest.RunId) -OperationId ([string]$row.OriginalOperationId) -Sequence ([long]$row.Ordinal) -Phase Intent -SourceEntryId ([string]$row.SourceEntryId) -ArchivePst ([string]$Manifest.TargetPstPreview) -SourceStoreId ([string]$script:fixture.RawStoreId) -SourceFolderPath '\\info@stios.ru\Входящие' -TargetFolderPath ([string]$row.TargetFolderPath) -Message ('ARCH3w evidence-only; seal='+[string]$Manifest.SealSha256+'; fullOriginalWitness='+[string]$row.FullOriginalWitnessSha256+'; no COM Move/MoveClaimed.'))
        }
    }
}
Describe 'ARCH3w original journal exactly-ten protected real test POP3 Intents no Move' {
    BeforeEach {
        $script:m=New-ARCH3wTestManifest
        Mock Assert-OPA265ARCH3wSealedSource {$script:fixture.Seal}
    }
    It 'reuses original ARCH3v SHA evidence for all ten original operations' {
        $script:m.Rows.Count | Should -Be 10
        $script:m.TotalAttachmentCount | Should -Be 12
        $script:m.PrepareDigest | Should -Match '^[a-f0-9]{64}$'
        (Get-OPA265ARCH3wPrepareDigest -Manifest $script:m) | Should -BeExactly $script:m.PrepareDigest
        $script:m.WriterPermit | Should -BeFalse
        $script:m.MoveClaimed | Should -BeFalse
    }
    It 'binds exactly original ARCH3v operation identity and full witness SHA' {
        (Assert-OPA265ARCH3wManifestMatchesSeal -Manifest $script:m -Seal $script:fixture.Seal) | Should -BeTrue
        foreach($r in $script:m.Rows){$r.OriginalOperationId | Should -BeExactly ('ARCH3b-'+$r.OriginalContractSha256)}
    }
    It 'rejects a changed original full semantic witness SHA' {
        $script:m.Rows[4].FullOriginalWitnessSha256='f'*64
        {Assert-OPA265ARCH3wManifestMatchesSeal -Manifest $script:m -Seal $script:fixture.Seal} | Should -Throw
    }
    It 'rejects changed original operation contract digest' {
        $script:m.Rows[4].OriginalContractSha256='f'*64
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects duplicate source selector EntryID' {
        $script:m.Rows[4].SourceEntryId=$script:m.Rows[0].SourceEntryId
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects duplicate operation SHA across different EntryIDs' {
        $script:m.Rows[4].OriginalOperationId=$script:m.Rows[0].OriginalOperationId
        $script:m.Rows[4].OriginalContractSha256=$script:m.Rows[0].OriginalContractSha256
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects missing tenth original source' {
        $script:m.Rows=@($script:m.Rows | Select-Object -First 9)
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects reordered original source witnesses' {
        $script:m.Rows[3].Ordinal=1
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects wrong original target folder for one mail' {
        $script:m.Rows[3].TargetFolderPath='2020\Wrong'
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects missing source seal SHA' {
        $script:m.SealSha256='NOPE'
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects original index SHA drift from external sealed source' {
        $script:m.OriginalIndexSha256=('f'*64)
        {Assert-OPA265ARCH3wManifestMatchesSeal -Manifest $script:m -Seal $script:fixture.Seal} | Should -Throw
    }
    It 'rejects wrong second pre-existing original archive part' {
        $script:m.ExistingArchiveParts[1].Part=4
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects original part digest drift' {
        $old=$script:m.PrepareDigest
        $script:m.ExistingArchiveParts[0].Sha256='3'*64
        (Get-OPA265ARCH3wPrepareDigest -Manifest $script:m) | Should -Not -BeExactly $old
    }
    It 'rejects missing original archive part' {
        $script:m.ExistingArchiveParts=@($script:m.ExistingArchiveParts | Select-Object -First 1)
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects any MoveClaimed flag before COM Move stage' {
        $script:m.MoveClaimed=$true
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects unsafe real PST or DuplicateIndex writer flags' {
        $script:m.OriginalDuplicateIndexWritten=$true
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
        $script:m.OriginalDuplicateIndexWritten=$false
        $script:m.ArchivePstCreated=$true
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects mismatched total 12 real source attachment count' {
        $script:m.Rows[9].AttachmentCount=4
        {Get-OPA265ARCH3wPrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects a forged manifest PrepareDigest' {
        $script:m.PrepareDigest='f'*64
        {Assert-OPA265ARCH3wManifestMatchesSeal -Manifest $script:m -Seal $script:fixture.Seal} | Should -Throw
    }
    It 'original journal writer persists 10 exact original Intent events with SHA and readback' {
        $run=[guid]::NewGuid().ToString('D')
        $l=Get-OPA265ARCH3wLayout -RunId $run
        $script:m.RunId=$run
        $script:m.PrepareDigest=Get-OPA265ARCH3wPrepareDigest -Manifest $script:m
        $script:fixture.Seal.RunId=$run
        try{
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $l
            $ms=Write-OPA265ARCH3cJsonOnce -Path ([string]$l.ManifestPath) -Record $script:m
            New-ARCH3wOriginalJournal -Layout $l -Manifest $script:m
            $js=(Get-FileHash -LiteralPath ([string]$l.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
            $w=Test-OPA265ARCH3wPreparedReadback -Layout $l -ManifestSha256 $ms -JournalSha256 $js -SealSha256 ('d'*64)
            $w.Status | Should -BeExactly 'TenOriginalOperationJournalRealTestPstIntentsIndependentlyVerifiedNoMove'
            $w.OriginalJournalEventCount | Should -Be 10
            $w.MoveClaimed | Should -BeFalse
            $w.WriterPermit | Should -BeFalse
        }finally{
            $script:fixture.Seal.RunId='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
            if([IO.Directory]::Exists([string]$l.Root)){Remove-Item -LiteralPath $l.Root -Recurse -Force}
        }
    }
    It 'protected journal cannot be automatically replayed if only nine Intent rows exist' {
        $run=[guid]::NewGuid().ToString('D');$l=Get-OPA265ARCH3wLayout -RunId $run
        $script:m.RunId=$run;$script:m.PrepareDigest=Get-OPA265ARCH3wPrepareDigest -Manifest $script:m
        $script:fixture.Seal.RunId=$run
        try{
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $l
            $ms=Write-OPA265ARCH3cJsonOnce -Path ([string]$l.ManifestPath) -Record $script:m
            New-ARCH3wOriginalJournal -Layout $l -Manifest $script:m -Number 9
            $js=(Get-FileHash -LiteralPath ([string]$l.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
            {Test-OPA265ARCH3wPreparedReadback -Layout $l -ManifestSha256 $ms -JournalSha256 $js -SealSha256 ('d'*64)} | Should -Throw
        }finally{
            $script:fixture.Seal.RunId='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
            if([IO.Directory]::Exists([string]$l.Root)){Remove-Item -LiteralPath $l.Root -Recurse -Force}
        }
    }
    It 'rejects a truncated original SHA journal tail without silent recovery' {
        $run=[guid]::NewGuid().ToString('D');$l=Get-OPA265ARCH3wLayout -RunId $run
        $script:m.RunId=$run;$script:m.PrepareDigest=Get-OPA265ARCH3wPrepareDigest -Manifest $script:m
        $script:fixture.Seal.RunId=$run
        try{
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $l
            $ms=Write-OPA265ARCH3cJsonOnce -Path ([string]$l.ManifestPath) -Record $script:m
            New-ARCH3wOriginalJournal -Layout $l -Manifest $script:m
            [IO.File]::AppendAllText([string]$l.JournalPath,'TAMPER')
            $js=(Get-FileHash -LiteralPath ([string]$l.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
            {Test-OPA265ARCH3wPreparedReadback -Layout $l -ManifestSha256 $ms -JournalSha256 $js -SealSha256 ('d'*64)} | Should -Throw
        }finally{
            $script:fixture.Seal.RunId='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
            if([IO.Directory]::Exists([string]$l.Root)){Remove-Item -LiteralPath $l.Root -Recurse -Force}
        }
    }
    It 'refuses overwrite of an already written immutable intent manifest' {
        $run=[guid]::NewGuid().ToString('D');$l=Get-OPA265ARCH3wLayout -RunId $run
        try{
            New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $l
            [void](Write-OPA265ARCH3cJsonOnce -Path ([string]$l.ManifestPath) -Record $script:m)
            {Write-OPA265ARCH3cJsonOnce -Path ([string]$l.ManifestPath) -Record $script:m} | Should -Throw
        }finally{if([IO.Directory]::Exists([string]$l.Root)){Remove-Item -LiteralPath $l.Root -Recurse -Force}}
    }
    It 'Plan does not require Outlook COM when protected seal already exists' {
        # The fake source path is intentionally absent: Plan must refuse to
        # claim a real test PST exists, and never create one.
        {Invoke-OPA265ARCH3wTenOriginalIntent -Mode Plan -RunId ([guid]::NewGuid().ToString('D')) -SealSha256 ('d'*64) -ExpectedAuditSha256 ('a'*64) -ExpectedPreviewSha256 ('b'*64) -ExpectedOriginalIndexSha256 ('c'*64)} | Should -Throw
    }
    It 'Review refuses a flag that could authorize re-Prepare' {
        {Invoke-OPA265ARCH3wTenOriginalIntent -Mode Review -RunId ([guid]::NewGuid().ToString('D')) -SealSha256 ('d'*64) -ManifestSha256 ('a'*64) -JournalSha256 ('b'*64) -ConfirmPrepareIntent} | Should -Throw
    }
    It 'Prepare requires explicit consent and a pinned PrepareDigest' {
        {Invoke-OPA265ARCH3wTenOriginalIntent -Mode Prepare -RunId ([guid]::NewGuid().ToString('D')) -SealSha256 ('d'*64) -ExpectedAuditSha256 ('a'*64) -ExpectedPreviewSha256 ('b'*64) -ExpectedOriginalIndexSha256 ('c'*64)} | Should -Throw
    }
    It 'new entrypoint/module have UTF8 BOM and cannot execute COM Move or shared index writer' {
        foreach($p in @('Invoke-ARCH3w.ps1','Core/Archive/ARCH3wTenOriginalIntents.ps1')){
            $full=Join-Path $script:root $p
            $bytes=[IO.File]::ReadAllBytes($full)
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
            $code=[IO.File]::ReadAllText($full)
            $code | Should -Not -Match '\.Move\s*\('
            $code | Should -Not -Match '\.AddStoreEx\s*\('
            $code | Should -Not -Match 'Add-OPADuplicateEntry\s'
            $code | Should -Not -Match '\bMoveClaimed\s*=\s*\$true'
        }
    }
}
