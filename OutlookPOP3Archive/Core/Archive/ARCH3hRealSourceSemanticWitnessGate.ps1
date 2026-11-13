#requires -Version 5.1
# ARCH3h: read-only FULL original semantic witness of one exact operator-pinned
# real POP3 Inbox MailItem. No archive or durable operation writer.
# The original attachment witness may create PRIVATE temporary payload copies
# for SHA256, which it cleans up. It never writes any PST or journal.
. (Join-Path $PSScriptRoot 'ARCH3gExistingArchiveCollisionGate.ps1')
. (Join-Path $PSScriptRoot 'ARCH3dOriginalMoverBoundary.ps1')

function Assert-OPA265ARCH3hPinnedPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Observed,
        [Parameter(Mandatory=$true)][string]$SourceEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedSourceFolderEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedStoreIdSha256,
        [Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$ExpectedSourcePstLengthBytes,
        [Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$ExpectedExistingArchiveLengthBytes,
        [Parameter(Mandatory=$true)][ValidateRange(0,256)][int]$ExpectedAttachmentCount,
        [Parameter(Mandatory=$true)][datetime]$ExpectedArchiveDate
    )
    $id=Assert-OPA265ARCH3gSourceEntryId -SourceEntryId $SourceEntryId
    if(-not [bool]$Observed.ExactInboxItemIndependentlyLocated -or
       -not [bool]$Observed.ExistingYearArchiveCollision -or
       [int]$Observed.ExistingPartCount -ne 1 -or
       [int]$Observed.ExistingParts[0].Part -ne 1 -or
       [string]$Observed.SourceEntryId -cne $id -or
       [string]$Observed.SourceFolderEntryId -cne $ExpectedSourceFolderEntryId -or
       [string]$Observed.SourceStoreIdSha256 -cne $ExpectedStoreIdSha256 -or
       [int64]$Observed.SourcePstLengthBytes -ne $ExpectedSourcePstLengthBytes -or
       [int64]$Observed.ExistingParts[0].FileLengthBytes -ne $ExpectedExistingArchiveLengthBytes -or
       [int]$Observed.AttachmentCount -ne $ExpectedAttachmentCount -or
       ([datetime]$Observed.SourceArchiveDate).Ticks -ne $ExpectedArchiveDate.Ticks -or
       [bool]$Observed.WriterPermit -or [bool]$Observed.ProductionReady){
        throw 'ARCH3h pinned ARCH3g real Inbox/StoreID/part1/source/attachment/date evidence drift; STOP.'
    }
    return $true
}

function Invoke-OPA265ARCH3hPinnedSemanticWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Witness')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$SourceEntryId,
        [Parameter(Mandatory=$true)][ValidateRange(1900,2100)][int]$ArchiveYear,
        [Parameter(Mandatory=$true)][string]$ExpectedSourceFolderEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedStoreIdSha256,
        [Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$ExpectedSourcePstLengthBytes,
        [Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$ExpectedExistingArchiveLengthBytes,
        [Parameter(Mandatory=$true)][ValidateRange(0,256)][int]$ExpectedAttachmentCount,
        [Parameter(Mandatory=$true)][datetime]$ExpectedArchiveDate,
        [switch]$IncludeFullWitness
    )
    $p=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -ceq 'Witness')
    $id=Assert-OPA265ARCH3gSourceEntryId -SourceEntryId $SourceEntryId
    if($ExpectedSourceFolderEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$' -or
       $ExpectedStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $ExpectedArchiveDate.Year -ne $ArchiveYear){
        throw 'ARCH3h malformed pinned evidence.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3h.Plan.1'
            Status='ExactRealMailFullSemanticWitnessPlannedOnlyNoOutlook'
            SourcePst=$p;SourceEntryId=$id;ArchiveYear=$ArchiveYear
            OriginalFullBodyHtmlRecipientAttachmentHashRequired=$true
            PinnedExistingArchivePart1Required=$true
            OriginalMailMoverUsedForMoving=$false
            OutlookContacted=$false;FullWitnessCaptured=$false
            NoPstOrJournalWrites=$true;LiveMovePerformed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
       [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3h full witness requires Windows PowerShell 5.1 -STA.'
    }
    $g=Invoke-OPA265ARCH3gExistingArchiveGate -Mode Audit -SourcePst $p -SourceEntryId $id -ArchiveYear $ArchiveYear
    $pin=@{
        Observed=$g;SourceEntryId=$id;ExpectedSourceFolderEntryId=$ExpectedSourceFolderEntryId
        ExpectedStoreIdSha256=$ExpectedStoreIdSha256
        ExpectedSourcePstLengthBytes=$ExpectedSourcePstLengthBytes
        ExpectedExistingArchiveLengthBytes=$ExpectedExistingArchiveLengthBytes
        ExpectedAttachmentCount=$ExpectedAttachmentCount
        ExpectedArchiveDate=$ExpectedArchiveDate
    }
    [void](Assert-OPA265ARCH3hPinnedPreflight @pin)
    $layout=Get-OPA265ARCH2dLayout -RunId '11111111-2222-4333-8444-555555555555' -LocalAppData $env:LOCALAPPDATA
    $session=$null;$mail=$null;$parent=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $p
        if(-not [bool]$session.Scope.Approved -or
           [int]$session.OutlookProcessId -ne [int]$g.OutlookProcessId -or
           [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$g.OutlookProcessStartUtcTicks){
            throw 'ARCH3h Outlook process/profile session changed during witness; STOP.'
        }
        $storeId=[string]$session.SourceStore.StoreID
        if((Get-OPA265ARCH2bTextSha256 -Text $storeId) -cne $ExpectedStoreIdSha256 -or
           $storeId -cne [string]$session.Scope.SourceStoreId){
            throw 'ARCH3h POP3 StoreID changed before full witness.'
        }
        $mail=$session.Namespace.GetItemFromID($id,$storeId)
        if($null -eq $mail -or [int]$mail.Class -ne 43 -or [string]$mail.EntryID -cne $id){
            throw 'ARCH3h exact original MailItem changed.'
        }
        $parent=$mail.Parent
        if($null -eq $parent -or
           [string]$parent.EntryID -cne $ExpectedSourceFolderEntryId -or
           [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
           [string]$parent.StoreID -cne $storeId){
            throw 'ARCH3h selected MailItem left exact POP3 Inbox.'
        }
        $date=Get-OPAArchiveItemDate -Item $mail
        if($null -eq $date -or ([datetime]$date).Ticks -ne $ExpectedArchiveDate.Ticks){
            throw 'ARCH3h original archive date changed.'
        }
        if([int]$mail.Attachments.Count -ne $ExpectedAttachmentCount){
            throw 'ARCH3h attachment count drift before full hash.'
        }
        $witness=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $witness) -or
           [int]$witness.AttachmentCount -ne $ExpectedAttachmentCount){
            throw 'ARCH3h original semantic witness invalid.'
        }
        $digest=Get-OPA265ARCH3dOriginalWitnessHash -Witness $witness
        # Recheck file and source scope after potentially expensive temp SHA256.
        if([int64]([IO.FileInfo]::new($p)).Length -ne $ExpectedSourcePstLengthBytes -or
           [int64]([IO.FileInfo]::new([string]$g.ExistingParts[0].Path)).Length -ne $ExpectedExistingArchiveLengthBytes -or
           [string]$mail.EntryID -cne $id -or
           [string]$parent.EntryID -cne $ExpectedSourceFolderEntryId){
            throw 'ARCH3h source or existing archive changed while hashing; STOP.'
        }
        $result=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3h.OriginalSemanticWitness.1'
            Status='RealSourceFullOriginalSemanticWitnessComputedNoMove'
            SourcePst=$p;SourceEntryId=$id
            SourceStoreIdSha256=$ExpectedStoreIdSha256
            SourceFolderEntryId=$ExpectedSourceFolderEntryId
            ArchiveYear=$ArchiveYear;ArchiveDate=[datetime]$date
            ExistingArchivePart1Path=[string]$g.ExistingParts[0].Path
            ExistingArchivePart1LengthBytes=$ExpectedExistingArchiveLengthBytes
            NextUnusedPartPathPreview=[string]$g.NextUnusedPartPathPreview
            OriginalWitnessSchema=[string]$witness.Schema
            OriginalWitnessSha256=$digest
            BodySha256=[string]$witness.BodySha256
            HtmlBodySha256=[string]$witness.HtmlBodySha256
            RecipientDigestSha256=[string]$witness.OrderedRecipientDigestSha256
            AttachmentCount=[int]$witness.AttachmentCount
            AttachmentPayloadSha256=@($witness.Attachments | ForEach-Object { [string]$_.PayloadSha256 })
            FullWitnessCaptured=$true
            FullWitnessPersisted=$false
            RequiresExternalWitnessShaPin=$true
            AttachmentTemporaryCopiesMayBeCreated=$true
            OriginalSourcePstModifiedByTool=$false
            NoPstOrJournalWrites=$true;LiveMovePerformed=$false
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
        # Internal opt-in for ARCH3i immutable evidence. Public ARCH3h entrypoint
        # does not expose this switch or print the full witness object.
        if($IncludeFullWitness){$result | Add-Member -NotePropertyName FullWitness -NotePropertyValue $witness}
        return $result
    } finally{
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $mail
        Close-OPA265ARCH2dSession -Session $session
    }
}
