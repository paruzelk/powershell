#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1')
    function New-ARCH3w1SyntheticCase {
        $id='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
        $source='C:\OPA-ARCH3w1-SYNTH\info@stios.ru.pst'
        $rows=New-Object 'System.Collections.Generic.List[object]'
        $counts=@(0,1,1,1,2,2,0,0,0,5)
        for($i=0;$i -lt 10;$i++){
            $idHex=('{0:X16}' -f ($i+1))
            $c=Get-OPA265ARCH3bDigest -Parts @('ARCH3w1 synthetic contract',$idHex)
            $w=Get-OPA265ARCH3bDigest -Parts @('ARCH3w1 synthetic original witness',$idHex)
            [void]$rows.Add([pscustomobject][ordered]@{
                Ordinal=($i+1);SourceEntryId=$idHex
                OriginalOperationId=('ARCH3b-'+$c)
                OriginalContractSha256=$c
                FullOriginalWitnessSha256=$w
                TargetFolderPath='2020\Входящие'
                AttachmentCount=$counts[$i]
            })
        }
        $seal=[pscustomobject]@{
            RunId=$id;SourcePst=$source;BatchSize=10
            SourcePstLengthBytes=[long]7735903232
            SealSha256=('d'*64);AuditSha256=('a'*64);PreviewSha256=('b'*64)
            OriginalIndexSha256=('c'*64);SourceStoreIdSha256=('e'*64)
            TargetPstPreview='C:\OPA-ARCH3w1-SYNTH\info@stios.ru.Archive-2020-03.pst'
            TotalAttachmentCount=12;Rows=@($rows.ToArray())
        }
        $parts=@(
            [pscustomobject][ordered]@{
                Part=1;Path='C:\OPA-ARCH3w1-SYNTH\info@stios.ru.Archive-2020.pst'
                LengthBytes=[long]271360
                Sha256='8bc491f7b5e7b71e5458f88b01fa684f22270b425d7eca3fba572b1914e2514b'
                ProofKind='OriginalPstBinarySha256';OriginalWitnessSha256='';ArchiveEntryId=''
            },
            [pscustomobject][ordered]@{
                Part=2;Path='C:\OPA-ARCH3w1-SYNTH\info@stios.ru.Archive-2020-02.pst'
                LengthBytes=[long]525312;Sha256=('f'*64)
                ProofKind='OriginalArchiveVerifierFullSemanticSha256'
                OriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
                ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
            }
        )
        return [pscustomobject]@{Seal=$seal;Parts=$parts}
    }
    $script:case=New-ARCH3w1SyntheticCase
    function New-ARCH3w1FixtureManifest {
        $m=New-OPA265ARCH3w1Manifest -Seal $script:case.Seal -SealSha256 ('d'*64) -ExistingArchiveParts $script:case.Parts
        return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $m -Depth 30 -Compress))
    }
}
Describe 'ARCH3w1 original Part2 historical full semantic proof; binary bytes are not an Intent gate' {
    BeforeEach {$script:m=New-ARCH3w1FixtureManifest}
    It 'binds ten original ARCH3v entry witnesses and 12 attachments to stage-specific prepare digest' {
        $script:m.Rows.Count | Should -Be 10
        $script:m.TotalAttachmentCount | Should -Be 12
        $script:m.PrepareDigest | Should -Match '^[a-f0-9]{64}$'
        $script:m.Schema | Should -BeExactly '2.6.5-ARCH3w1.TenOriginalIntentManifest.1'
        $script:m.ExistingArchiveParts[1].ProofKind | Should -BeExactly 'OriginalArchiveVerifierFullSemanticSha256'
        (Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m) | Should -BeExactly $script:m.PrepareDigest
    }
    It 'binds Part1 exact original physical SHA and size' {
        $script:m.ExistingArchiveParts[0].Sha256='3'*64
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects Part1 physical length drift' {
        $script:m.ExistingArchiveParts[0].LengthBytes=271361
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects Part2 original full witness SHA drift' {
        $script:m.ExistingArchiveParts[1].OriginalWitnessSha256='1'*64
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects Part2 original destination archive EntryID drift' {
        $script:m.ExistingArchiveParts[1].ArchiveEntryId='0'*64
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects metadata bypass that mislabels Part2 semantic proof as raw physical SHA' {
        $script:m.ExistingArchiveParts[1].ProofKind='OriginalPstBinarySha256'
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects Part2 size changes even if MAPI content remains unchanged' {
        $script:m.ExistingArchiveParts[1].LengthBytes=525313
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'does not include untrusted raw Part2 file SHA telemetry into stable PrepareDigest' {
        $before=$script:m.PrepareDigest
        $script:m.ExistingArchiveParts[1] | Add-Member -NotePropertyName PhysicalSha256Observed -NotePropertyValue ('3'*64)
        (Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m) | Should -BeExactly $before
        $script:m.ExistingArchiveParts[1].PhysicalSha256Observed='4'*64
        (Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m) | Should -BeExactly $before
    }
    It 'does bind the original Part2 full semantic digest into PrepareDigest' {
        $before=$script:m.PrepareDigest
        $script:m.ExistingArchiveParts[1].Sha256='3'*64
        (Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m) | Should -Not -BeExactly $before
    }
    It 'rejects Part2 proof completely absent' {
        $script:m.ExistingArchiveParts[1].Sha256=''
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'retains protected source full content witness contract' {
        (Assert-OPA265ARCH3w1ManifestMatchesSeal -Manifest $script:m -Seal $script:case.Seal) | Should -BeTrue
    }
    It 'rejects original source semantic witness drift' {
        $script:m.Rows[9].FullOriginalWitnessSha256='2'*64
        {Assert-OPA265ARCH3w1ManifestMatchesSeal -Manifest $script:m -Seal $script:case.Seal} | Should -Throw
    }
    It 'rejects duplicate source identity' {
        $script:m.Rows[1].SourceEntryId=$script:m.Rows[0].SourceEntryId
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects any MoveClaimed or original index writer' {
        $script:m.MoveClaimed=$true
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
        $script:m.MoveClaimed=$false
        $script:m.OriginalDuplicateIndexWritten=$true
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'rejects any extra original archived source case' {
        $script:m.Rows=@($script:m.Rows | Select-Object -First 9)
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'does not allow skipped original zero attachment witness' {
        $script:m.Rows[0].FullOriginalWitnessSha256=''
        {Get-OPA265ARCH3w1PrepareDigest -Manifest $script:m} | Should -Throw
    }
    It 'requires dedicated ARCH3w1 root rather than existing ARCH3w evidence root' {
        $l=Get-OPA265ARCH3w1Layout -RunId $script:case.Seal.RunId
        $l.Root | Should -Match 'OPA265-ARCH3w1-'
        $l.JournalPath | Should -Match 'original-operation-journal.jsonl'
    }
    It 'stage module loads original ARCH3q postcommit pinned evidence reader, not old precommit ARCH3p status' {
        $s=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1'))
        $s | Should -Match 'Get-OPA265ARCH3qPinnedStages -State'
        $s | Should -Match 'Get-OPA265ARCH3rCompletedRealCheckpoint -Mode Audit'
        $s | Should -Match 'Test-OPAArchiveMoves -Namespace'
        $s | Should -Match 'Compare-OPA265ARCH2bMailSemanticWitness -Source'
        $s | Should -Not -Match 'Get-OPA265ARCH3pClaimChain\s+-RunId'
    }
    It 'no new original production Archive/Resume/Auto or COM Move writer is introduced' {
        $path=Join-Path $script:root 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1'
        $source=[IO.File]::ReadAllText($path)
        $source | Should -Not -Match '\.Move\s*\('
        $source | Should -Not -Match '\.AddStoreEx\s*\('
        $source | Should -Not -Match 'Add-OPADuplicateEntry\s'
        $source | Should -Not -Match '\bMoveClaimed\s*=\s*\$true'
    }
    It 'new PS files use UTF8 BOM' {
        foreach($relative in @('Invoke-ARCH3w1.ps1','Core/Archive/ARCH3w1SemanticPart2Intents.ps1','Tests/Archive/ARCH3w1SemanticPart2Intents.Tests.ps1')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:root $relative))
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'original ARCH3w1 physical Part2 SHA is not fetched by stage gating routine' {
        $file=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1'))
        $between=$file.Substring($file.IndexOf('function Get-OPA265ARCH3w1OriginalYearParts {'))
        $between=$between.Substring(0,$between.IndexOf('function Assert-OPA265ARCH3w1SealedSource {'))
        $between | Should -Not -Match 'Get-FileHash\s+-LiteralPath\s+\$second'
        $between | Should -Match 'Test-OPA265ARCH3w1LiveOriginalPart2'
    }
}
