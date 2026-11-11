#requires -Version 5.1
# ARCH1: read-only source audit. Never contact Outlook, PSTs, mail or registry.
[CmdletBinding()]
param([ValidateSet('Plan','Audit')][string]$Mode='Audit')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(-not [IO.Directory]::Exists($projectRoot)){
    throw 'ARCH1 project directory missing.'
}
$paths=[ordered]@{
    EntryPoint='OutlookPOP3Archive.ps1'
    Mover='Core/Archive/MailMover.ps1'
    Verifier='Core/Archive/ArchiveVerifier.ps1'
    Grouping='Core/Archive/ArchiveGrouping.ps1'
    Planner='Core/Archive/ArchivePlanner.ps1'
    Journal='Core/Archive/OperationJournal.ps1'
    DuplicateIndex='Core/Archive/DuplicateIndex.ps1'
    SystemFolders='Core/Archive/SystemFolders.ps1'
    Release='RELEASE.json'
}
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH1.ReadOnlyPlan.1'
        Status='SourceAuditOnlyNoOutlookNoFileWrites'
        ProjectRoot=$projectRoot
        SourceFileCount=$paths.Count
        ReadsOnlyProjectCodeAndReleaseMetadata=$true
        InspectMailbox=$false
        OpenOutlook=$false
        ModifyProjectOrPst=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
. (Join-Path $projectRoot 'Core/Runtime/ARCH1DeliveryReadinessPolicy265.ps1')
$evidence=[ordered]@{}
$hashes=New-Object 'System.Collections.Generic.List[object]'
foreach($key in @($paths.Keys)){
    $path=Join-Path $projectRoot $paths[$key]
    if(-not [IO.File]::Exists($path)){
        throw ('ARCH1 required source missing: '+[string]$paths[$key])
    }
    if($key -ceq 'Release'){
        $value=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }else{
        $value=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }
    $evidence[$key]=$value
    $hashes.Add([pscustomobject][ordered]@{
        Path=[string]$paths[$key]
        Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}
$r=Test-OPA265ARCH1DeliveryReadiness -Evidence ([pscustomobject]$evidence)
return [pscustomobject][ordered]@{
    Schema='2.6.5-ARCH1.ReadOnlySourceAudit.1'
    Status=[string]$r.Status
    EvidenceKind='StaticSourceMarkersOnly'
    ProjectRoot=$projectRoot
    ExistingArchiveRuntimeNotModified=$true
    OutlookComAccess=$false
    AnyPstOrMailRead=$false
    AnyPstOrMailWriter=$false
    AnyEvidenceFileWrite=$false
    CurrentReleaseBuild=[string]$evidence['Release'].Build
    ExternalPackageSeries='2.6.5-ARCH1-dev'
    SourceSha256=@($hashes.ToArray())
    Readiness=$r
    WriterPermit=$false
    ProductionReady=$false
}
