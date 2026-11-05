#requires -Version 5.1
# BW4k7v fresh isolated PST helper: synthetic fixtures only; NO Move/Delete/Send.
. (Join-Path $PSScriptRoot 'BW4k7uSyntheticBatch265.ps1')
function Assert-OPA265BW4k7vSuiteId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $SuiteId -or $SuiteId -ceq 'd1a68868-acf5-4c70-860d-5521e1ce2836'){
        throw 'BW4k7v requires NEW canonical lowercase nonhistorical GUID.'
    }
    return $true
}
function Get-OPA265BW4k7vLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    [void](Assert-OPA265BW4k7vSuiteId -SuiteId $SuiteId)
    if(-not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\\',[StringComparison]::Ordinal) -or
       -not [IO.Directory]::Exists($LocalAppData)){
        throw 'BW4k7v requires existing local non-UNC LOCALAPPDATA.'
    }
    $root=[IO.Path]::GetFullPath((Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7v-Isolated'))
    $dir=Join-Path $root ('suite-'+$SuiteId)
    $file=Join-Path $dir ('OPA265-BW4k7v-'+$SuiteId+'.pst')
    $manifest=Join-Path $dir 'premovereadonly-manifest.json'
    return [pscustomobject][ordered]@{
        SuiteId=$SuiteId;Root=$root;SuiteDirectory=$dir
        SourcePst=$file;ManifestPath=$manifest
        AttachmentScratchDirectory=(Join-Path $dir 'transient')
        FixtureRootFolderName=('OPA265-BW4k7v-'+$SuiteId)
        NewPstMustNotAlreadyExist=$true
        OnlyLocalAppDataPathAllowed=$true
        ProductionPstPathAccepted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Assert-OPA265BW4k7vSafePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][ValidateSet('Create','Review')][string]$Mode)
    [void](Assert-OPA265BW4k7vSuiteId -SuiteId ([string]$Layout.SuiteId))
    $p=Get-OPA265BW4k7vLayout -SuiteId ([string]$Layout.SuiteId) -LocalAppData $env:LOCALAPPDATA
    foreach($key in @('Root','SuiteDirectory','SourcePst','ManifestPath','AttachmentScratchDirectory','FixtureRootFolderName')){
        if([string]$Layout.$key -cne [string]$p.$key){throw ('BW4k7v forged path: '+$key)}
    }
    foreach($dir in @([string]$p.Root,[string]$p.SuiteDirectory,
        [string]$p.AttachmentScratchDirectory)){
        if([IO.Directory]::Exists($dir) -and
           (([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4k7v reparse/symlink fixture directory rejected.'
        }
    }
    if($Mode -eq 'Create'){
        if([IO.Directory]::Exists($p.SuiteDirectory) -or
           [IO.File]::Exists($p.SourcePst) -or
           [IO.File]::Exists($p.ManifestPath)){
            throw 'BW4k7v fixture already exists; never recreate or overwrite.'
        }
    }else{
        if(-not [IO.File]::Exists($p.SourcePst) -or
           -not [IO.File]::Exists($p.ManifestPath)){
            throw 'BW4k7v no original PST plus original manifest: stop; never reconstruct.'
        }
    }
    return $true
}
function Get-OPA265BW4k7vSha {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    return (Get-OPA265BW4k7uHash -Text $Text)
}
function Get-OPA265BW4k7vFixtureExpectations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId)
    $suite=New-OPA265BW4k7uSyntheticSuite -SuiteId $SuiteId
    [void](Assert-OPA265BW4k7uSyntheticSuite -Suite $suite)
    $rows=@($suite.Cases | Where-Object {$_.Kind -ceq 'Mail' -and $_.EligibleForArchive})
    if($rows.Count -ne 8){throw 'BW4k7v requires eight source-only synthetic Mail objects.'}
    return [pscustomobject][ordered]@{
        SuiteId=$SuiteId;SuiteManifestSha256=$suite.ManifestSha256
        FixtureItems=$rows;ExpectedCount=8
        SyntheticArchiveYears=@(2020,2021,2022,2023,2024,2025)
        RealMapiMessageDatesProven=$false
        GenuineSentItemsMessagesProven=$false
        NoOutlookMoveOrSend=$true
    }
}
function Get-OPA265BW4k7vExpectedSubject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item)
    return ('OPA265-BW4k7v-'+[string]$Item.CaseId)
}
function Assert-OPA265BW4k7vManifestShape {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Layout)
    $expected=Get-OPA265BW4k7vFixtureExpectations -SuiteId ([string]$Layout.SuiteId)
    if([string]$Manifest.Schema -cne '2.6.5-BW4k7v.ImmutableFreshDisposablePreMove.1' -or
       [string]$Manifest.SuiteId -cne [string]$Layout.SuiteId -or
       [string]$Manifest.SourcePst -cne [string]$Layout.SourcePst -or
       [string]$Manifest.FixtureRootFolderName -cne [string]$Layout.FixtureRootFolderName -or
       [string]$Manifest.SyntheticSuiteManifestSha256 -cne [string]$expected.SuiteManifestSha256 -or
       [int]$Manifest.FixtureCount -ne 8 -or
       [string]$Manifest.OutlookProfile -cne 'Outlook' -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.SourcePstStoreId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.RootFolderEntryId) -or
       [long]$Manifest.CreatingOutlookProcessStartUtcTicks -le 0 -or
       -not [bool]$Manifest.OnlySyntheticItemsCreated -or
       [bool]$Manifest.OutlookMoveExecuted -or
       [bool]$Manifest.OutlookSendExecuted -or
       [bool]$Manifest.ProductionPstOrMailboxModified -or
       [bool]$Manifest.DurableMoveIntentOrClaimCreated -or
       [bool]$Manifest.WriterPermit -or [bool]$Manifest.ProductionReady){
        throw 'BW4k7v manifest incomplete, forged or unsafe.'
    }
    $rows=@($Manifest.Items)
    if($rows.Count -ne 8){throw 'BW4k7v manifest must contain exactly eight synthetic mail witnesses.'}
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($row in $rows){
        $candidate=@($expected.FixtureItems | Where-Object {$_.CaseId -ceq $row.CaseId})
        if($candidate.Count -ne 1 -or -not $ids.Add([string]$row.CaseId) -or
           [string]$row.Name -cne [string]$candidate[0].Name -or
           [string]$row.Subject -cne (Get-OPA265BW4k7vExpectedSubject -Item $candidate[0]) -or
           [string]$row.Role -cne [string]$candidate[0].Role -or
           [int]$row.SyntheticArchiveYear -ne [int]$candidate[0].Year -or
           [string]$row.SourceFolderPath -cne [string]$candidate[0].SourceFolderPath -or
           [int]$row.Class -ne 43 -or [string]$row.MessageClass -cne 'IPM.Note' -or
           [string]::IsNullOrWhiteSpace([string]$row.EntryId) -or
           [string]::IsNullOrWhiteSpace([string]$row.FolderEntryId) -or
           [string]$row.StoreId -cne [string]$Manifest.SourcePstStoreId -or
           [string]$row.WitnessSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4k7v manifest witness is not an exact disposable candidate.'
        }
    }
    return $true
}
function Write-OPA265BW4k7vManifestOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][object]$Manifest)
    [void](Assert-OPA265BW4k7vManifestShape -Manifest $Manifest -Layout $Layout)
    $text=ConvertTo-Json -InputObject $Manifest -Depth 16
    $bytes=New-Object 'byte[]' 0
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
    $file=$null
    try{
        $file=[IO.File]::Open([string]$Layout.ManifestPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $file.Write($bytes,0,$bytes.Length)
        $file.Flush($true)
    }finally{if($null -ne $file){$file.Dispose()}}
    return [pscustomobject]@{
        ManifestPath=[string]$Layout.ManifestPath
        ManifestSha256=(Get-FileHash -LiteralPath $Layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        WrittenOnce=$true;MoveExecuted=$false;ProductionReady=$false
    }
}
function Read-OPA265BW4k7vManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256)
    if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k7v expected manifest SHA256 must be lowercase hexadecimal.'
    }
    [void](Assert-OPA265BW4k7vSafePath -Layout $Layout -Mode Review)
    $real=(Get-FileHash -LiteralPath $Layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($real -cne $ExpectedManifestSha256){
        throw 'BW4k7v pre-Move manifest file changed since create; STOP.'
    }
    $s=[IO.File]::ReadAllText([string]$Layout.ManifestPath,[Text.Encoding]::UTF8)
    $manifest=ConvertFrom-Json -InputObject $s
    [void](Assert-OPA265BW4k7vManifestShape -Manifest $manifest -Layout $Layout)
    return $manifest
}
