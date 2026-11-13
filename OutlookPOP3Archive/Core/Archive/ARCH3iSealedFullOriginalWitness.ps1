#requires -Version 5.1
# ARCH3i: persist the ORIGINAL ARCH2b complete semantic witness with an
# externally pinned ARCH3h digest. Evidence file only; never PST/Move/journal.
# No replay or overwrite. Readback is independent of Outlook and the source.
. (Join-Path $PSScriptRoot 'ARCH3hRealSourceSemanticWitnessGate.ps1')
. (Join-Path $PSScriptRoot 'ARCH3cDurableOperationLedger.ps1')

function Get-OPA265ARCH3iEvidenceLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId){
        throw 'ARCH3i requires new canonical lowercase GUID RunId.'
    }
    $base=[IO.Path]::GetFullPath($LocalAppData)
    $actualBase=[IO.Path]::GetFullPath($env:LOCALAPPDATA)
    if(-not [string]::Equals($base,$actualBase,[StringComparison]::OrdinalIgnoreCase) -or
       $base.StartsWith('\\') -or
       -not [IO.Directory]::Exists($base) -or
       (([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3i requires the current Windows user LOCALAPPDATA, not arbitrary output path.'
    }
    $dir=Join-Path $base ('OPA265-ARCH3i-'+$RunId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3i.EvidenceLayout.1'
        RunId=$RunId
        Root=$dir
        WitnessPath=(Join-Path $dir 'original-full-semantic-witness.json')
        LocalAppData=$base
    }
}

function New-OPA265ARCH3iPrivateEvidenceDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    if([IO.Directory]::Exists([string]$Layout.Root) -or
       [IO.File]::Exists([string]$Layout.Root)){
        throw 'ARCH3i evidence RunId directory already exists; never replay or overwrite.'
    }
    $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if($null -eq $currentSid){throw 'ARCH3i Windows user SID unavailable.'}
    $systemSid=New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
    $dacl=New-Object Security.AccessControl.DirectorySecurity
    $dacl.SetAccessRuleProtection($true,$false)
    $dacl.SetOwner($currentSid)
    $inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach($sid in @($currentSid,$systemSid)){
        $rule=New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $dacl.AddAccessRule($rule)
    }
    # Atomic protected DACL at directory creation; no inherited access window.
    [void][IO.Directory]::CreateDirectory([string]$Layout.Root,$dacl)
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
}

function Assert-OPA265ARCH3iFullWitnessPinned {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness,
          [Parameter(Mandatory=$true)][string]$ExpectedOriginalWitnessSha256)
    if($ExpectedOriginalWitnessSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3i requires canonical SHA256 from independently observed ARCH3h result.'
    }
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $Witness)){
        throw 'ARCH3i original ARCH2b witness schema incomplete; no evidence write.'
    }
    $digest=Get-OPA265ARCH3dOriginalWitnessHash -Witness $Witness
    if($digest -cne $ExpectedOriginalWitnessSha256){
        throw 'ARCH3i original full witness changed since operator ARCH3h PIN; no evidence write.'
    }
    return $digest
}

function New-OPA265ARCH3iWitnessEnvelope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Observed,
          [Parameter(Mandatory=$true)][object]$Witness,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$ExpectedOriginalWitnessSha256)
    if([string]$Observed.Schema -cne '2.6.5-ARCH3h.OriginalSemanticWitness.1' -or
       [string]$Observed.OriginalWitnessSha256 -cne $ExpectedOriginalWitnessSha256 -or
       -not [bool]$Observed.FullWitnessCaptured -or
       [bool]$Observed.FullWitnessPersisted -or
       [bool]$Observed.WriterPermit -or [bool]$Observed.LiveMovePerformed -or
       [int]$Observed.ArchiveYear -ne 2020 -or
       [string]$Observed.SourceEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$'){
        throw 'ARCH3i rejects forged/unexpected real source evidence.'
    }
    [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $Witness -ExpectedOriginalWitnessSha256 $ExpectedOriginalWitnessSha256)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3i.OriginalFullWitnessEnvelope.1'
        RunId=$RunId
        SourcePst=[string]$Observed.SourcePst
        SourceEntryId=[string]$Observed.SourceEntryId
        SourceFolderEntryId=[string]$Observed.SourceFolderEntryId
        SourceStoreIdSha256=[string]$Observed.SourceStoreIdSha256
        SourceArchiveYear=[int]$Observed.ArchiveYear
        ArchiveDateLocalTicks=[long]([datetime]$Observed.ArchiveDate).Ticks
        ExistingArchivePart1Path=[string]$Observed.ExistingArchivePart1Path
        ExistingArchivePart1LengthBytes=[long]$Observed.ExistingArchivePart1LengthBytes
        NextUnusedPartPathPreview=[string]$Observed.NextUnusedPartPathPreview
        OriginalWitnessSha256=$ExpectedOriginalWitnessSha256
        OriginalWitness=$Witness
        FullWitnessPersisted=$true
        FutureLiveWriterAuthorized=$false
        OriginalArchiveResumeAutoRemainClosed=$true
        LiveMovePerformed=$false
        ArchivePstOpenedOrCreated=$false
        OperationJournalWritten=$false
        DuplicateIndexWritten=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Test-OPA265ARCH3iReadback {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SealSha256)
    if(-not [IO.Directory]::Exists([string]$Layout.Root) -or
       (([IO.File]::GetAttributes([string]$Layout.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3i evidence directory missing/reparse point, STOP.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
    $file=[string]$Layout.WitnessPath
    if(-not [IO.File]::Exists($file) -or
       (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3i sealed full witness missing/reparse point, STOP.'
    }
    if(@([IO.Directory]::GetFileSystemEntries([string]$Layout.Root)).Count -ne 1){
        throw 'ARCH3i evidence directory contains unrecognized files; manual review.'
    }
    $sealed=Read-OPA265ARCH3cPinnedJson -Path $file -ExpectedSha256 $SealSha256
    if([string]$sealed.Schema -cne '2.6.5-ARCH3i.OriginalFullWitnessEnvelope.1' -or
       [string]$sealed.RunId -cne [string]$Layout.RunId -or
       [int]$sealed.SourceArchiveYear -ne 2020 -or
       [string]$sealed.SourceEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$' -or
       [string]$sealed.SourceStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [bool]$sealed.FullWitnessPersisted -or
       [bool]$sealed.LiveMovePerformed -or [bool]$sealed.WriterPermit -or
       [bool]$sealed.FutureLiveWriterAuthorized -or
       [bool]$sealed.OperationJournalWritten -or [bool]$sealed.DuplicateIndexWritten -or
       [bool]$sealed.ProductionReady){
        throw 'ARCH3i full witness envelope invalid/unsafe.'
    }
    [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $sealed.OriginalWitness -ExpectedOriginalWitnessSha256 ([string]$sealed.OriginalWitnessSha256))
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3i.SealReadback.1'
        Status='OriginalFullWitnessSealedAndIndependentlyReadBackNoMove'
        RunId=[string]$sealed.RunId
        SourcePst=[string]$sealed.SourcePst
        SourceEntryId=[string]$sealed.SourceEntryId
        SourceFolderEntryId=[string]$sealed.SourceFolderEntryId
        SourceStoreIdSha256=[string]$sealed.SourceStoreIdSha256
        ArchiveYear=[int]$sealed.SourceArchiveYear
        OriginalWitnessSha256=[string]$sealed.OriginalWitnessSha256
        FullWitnessSchema=[string]$sealed.OriginalWitness.Schema
        AttachmentCount=[int]$sealed.OriginalWitness.AttachmentCount
        SealSha256=$SealSha256
        SealPath=$file
        FullWitnessPersisted=$true
        IndependentReadbackPassed=$true
        ExistingArchivePstUnmodifiedByTool=$true
        ArchivePstOpenedOrCreated=$false
        JournalOrIndexWrites=$false
        LiveMovePerformed=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3iFullWitnessSeal {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Seal','Review')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [string]$SourcePst,
        [string]$SourceEntryId,
        [ValidateRange(1900,2100)][int]$ArchiveYear=2020,
        [string]$ExpectedSourceFolderEntryId,
        [string]$ExpectedStoreIdSha256,
        [long]$ExpectedSourcePstLengthBytes,
        [long]$ExpectedExistingArchiveLengthBytes,
        [ValidateRange(0,256)][int]$ExpectedAttachmentCount,
        [datetime]$ExpectedArchiveDate,
        [string]$ExpectedOriginalWitnessSha256,
        [string]$SealSha256,
        [switch]$ConfirmEvidenceWrite
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3i requires native Windows PowerShell 5.1.'
    }
    $layout=Get-OPA265ARCH3iEvidenceLayout -RunId $RunId
    if($Mode -ceq 'Review'){
        if($ConfirmEvidenceWrite -or $SealSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'ARCH3i Review requires pinned evidence SHA256 without write confirmation.'
        }
        return (Test-OPA265ARCH3iReadback -Layout $layout -SealSha256 $SealSha256)
    }
    if([string]::IsNullOrWhiteSpace($SourcePst) -or
       [string]::IsNullOrWhiteSpace($SourceEntryId) -or
       [string]::IsNullOrWhiteSpace($ExpectedSourceFolderEntryId) -or
       [string]::IsNullOrWhiteSpace($ExpectedStoreIdSha256) -or
       $ExpectedSourcePstLengthBytes -le 0 -or $ExpectedExistingArchiveLengthBytes -le 0 -or
       $ExpectedArchiveDate -eq [datetime]::MinValue -or
       $ExpectedOriginalWitnessSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3i Plan/Seal require all independently pinned ARCH3g/ARCH3h source values.'
    }
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -ceq 'Seal')
    $id=Assert-OPA265ARCH3gSourceEntryId -SourceEntryId $SourceEntryId
    if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
        throw 'ARCH3i RunId already exists, no replay or overwrite.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3i.Plan.1'
            Status='PinnedRealOriginalSemanticWitnessSealPlanNoOutlookOrWrites'
            RunId=$RunId;SourcePst=$source;SourceEntryId=$id
            ExpectedOriginalWitnessSha256=$ExpectedOriginalWitnessSha256
            EvidenceRoot=[string]$layout.Root
            OutlookContacted=$false
            EvidenceWritten=$false
            SourcePstWritten=$false
            AutomaticMoveRetryAllowed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if(-not $ConfirmEvidenceWrite){
        throw 'ARCH3i Seal requires explicit -ConfirmEvidenceWrite; no PST/Move permission.'
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3i Seal requires Windows PowerShell 5.1 -STA.'
    }
    if(-not $PSCmdlet.ShouldProcess([string]$layout.WitnessPath,'Seal original SHA256 witness in private LOCALAPPDATA evidence directory only')){
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3i.WhatIf.1';RunId=$RunId
            Status='EvidenceSealWhatIfNoWrites'
            WriterPermit=$false;ProductionReady=$false
        }
    }
    # Compute and externally re-pin all original field hashes BEFORE any
    # evidence-directory write. No PST or archive store writer is invoked.
    $pins=@{
        SourcePst=$source;SourceEntryId=$id;ArchiveYear=$ArchiveYear
        ExpectedSourceFolderEntryId=$ExpectedSourceFolderEntryId
        ExpectedStoreIdSha256=$ExpectedStoreIdSha256
        ExpectedSourcePstLengthBytes=$ExpectedSourcePstLengthBytes
        ExpectedExistingArchiveLengthBytes=$ExpectedExistingArchiveLengthBytes
        ExpectedAttachmentCount=$ExpectedAttachmentCount
        ExpectedArchiveDate=$ExpectedArchiveDate
    }
    $observed=Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Witness -IncludeFullWitness @pins
    if($null -eq $observed.FullWitness){
        throw 'ARCH3i original full witness not available; no evidence directory created.'
    }
    $envelope=New-OPA265ARCH3iWitnessEnvelope -Observed $observed -Witness $observed.FullWitness -RunId $RunId -ExpectedOriginalWitnessSha256 $ExpectedOriginalWitnessSha256
    New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
    $sealHash=Write-OPA265ARCH3cJsonOnce -Path ([string]$layout.WitnessPath) -Record $envelope
    # Read back from OS file, not the in-memory semantic object.
    return (Test-OPA265ARCH3iReadback -Layout $layout -SealSha256 $sealHash)
}
