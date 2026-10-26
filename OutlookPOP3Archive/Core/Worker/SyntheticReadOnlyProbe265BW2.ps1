#requires -Version 5.1
# BW2 isolated read-only inspection of one existing LIVE3 synthetic fixture.
# Dependencies are explicitly dot-sourced by parent and isolated child.
function Get-OPA265BW2FixtureProof {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,[Parameter(Mandatory=$true)][string]$SourcePst)
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $req=Read-OPAWorkerJson -Path $paths.RequestPath
    if ([string]$req.RunId -cne [string]$paths.RunId -or
        -not [string]::Equals([string]$req.SourcePst,[string]$paths.SourcePst,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW2 durable fixture request RunId/source PST mismatch.'
    }
    $paths=Assert-OPA264Live3Request -Request $req
    $sha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $journal=Read-OPAOperationJournal -Path $paths.JournalPath
    $claim=$null;$state=''
    if (-not [bool]$journal.TrailingPartial -and @($journal.Events).Count -eq 1 -and
        -not [IO.File]::Exists((Get-OPA264Live6ClaimPath -Paths $paths))) {
        [void](Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal)
        $state='UnresolvedIntent'
    } elseif (-not [bool]$journal.TrailingPartial -and @($journal.Events).Count -eq 2 -and
        [IO.File]::Exists((Get-OPA264Live6ClaimPath -Paths $paths))) {
        $claim=Read-OPAWorkerJson -Path (Get-OPA264Live6ClaimPath -Paths $paths)
        [void](Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal $journal -Claim $claim)
        $state='Reconciled'
    } else {
        throw 'BW2 refuses torn, duplicate, indeterminate, or unclaimed journal.'
    }
    if ($sha -cne (Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'BW2 journal changed during fixture proof.'
    }
    return [pscustomobject]@{
        Schema='2.6.5-BW2.FixtureProof.1'
        RunId=[string]$paths.RunId
        OperationId=[string]$req.OperationId
        SourcePst=[string]$paths.SourcePst
        ArchivePst=[string]$paths.ArchivePst
        State=$state
        JournalSha256=$sha
        ExpectedInternetMessageId=[string]$journal.Events[0].InternetMessageId
        ExpectedSubject=[string]$journal.Events[0].Subject
        ExpectedSizeBytes=[long]$journal.Events[0].Size
        ExpectedArchiveEntryId=$(if ($null -eq $claim) {''} else {[string]$claim.ArchiveEntryId})
        ApprovedArchiveSizeBytes=$(if ($null -eq $claim) {0} else {[long]$claim.ObservedArchiveSizeBytes})
        Paths=$paths
        Request=$req
    }
}
function Assert-OPA265BW2Payload {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Payload)
    $fields=@($Payload.PSObject.Properties.Name)
    foreach($field in @('Schema','RunId','SourcePst','OperationId','JournalSha256','State')) {
        if ($fields -cnotcontains $field) {throw ('BW2 required payload field missing: '+$field)}
    }
    if ($fields.Count -ne 6 -or
        [string]$Payload.Schema -cne '2.6.5-BW2.SyntheticProbeRequest.1' -or
        [string]$Payload.JournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Payload.State -cnotin @('UnresolvedIntent','Reconciled')) {
        throw 'BW2 payload scope invalid or extra fields supplied.'
    }
    $id=[guid]::Empty
    if (-not [guid]::TryParse([string]$Payload.OperationId,[ref]$id) -or $id -eq [guid]::Empty) {
        throw 'BW2 OperationId must be a nonempty GUID.'
    }
    $paths=Get-OPA264Live3Paths -RunId ([string]$Payload.RunId) -SourcePst ([string]$Payload.SourcePst)
    if ([string]$Payload.RunId -cne [string]$paths.RunId -or
        [string]$Payload.SourcePst -cne [string]$paths.SourcePst) {
        throw 'BW2 requires exact canonical RunId and source PST path.'
    }
    return $true
}
function Assert-OPA265BW2ObservedCounts {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$State,[int]$SourceCount,[int]$ArchiveCount,
          [int]$SourceMatches,[int]$ArchiveMatches)
    if ($State -cnotin @('UnresolvedIntent','Reconciled') -or
        $SourceCount -lt 0 -or $ArchiveCount -lt 0 -or
        $SourceMatches -lt 0 -or $ArchiveMatches -lt 0 -or
        $SourceMatches -gt $SourceCount -or $ArchiveMatches -gt $ArchiveCount) {
        throw 'BW2 impossible synthetic counts.'
    }
    if ($State -ceq 'UnresolvedIntent' -and
        $SourceCount -eq 1 -and $ArchiveCount -eq 0 -and
        $SourceMatches -eq 1 -and $ArchiveMatches -eq 0) {
        return 'NoMoveObserved'
    }
    if ($State -ceq 'Reconciled' -and
        $SourceCount -eq 0 -and $ArchiveCount -eq 1 -and
        $SourceMatches -eq 0 -and $ArchiveMatches -eq 1) {
        return 'MoveConfirmed'
    }
    throw 'BW2 synthetic contents disagree with durable journal state.'
}
function Assert-OPA265BW2MatchingMail {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,[Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][string]$ExpectedStoreId,
          [Parameter(Mandatory=$true)][string]$ExpectedFolderId,
          [Parameter(Mandatory=$true)][object]$Proof,[switch]$Archive)
    if ($null -eq $Mail -or [int]$Mail.Class -ne 43 -or
        [string]::IsNullOrWhiteSpace([string]$Mail.EntryID) -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$Folder.StoreID) -ObservedFolderEntryId ([string]$Folder.EntryID) -ExpectedStoreId $ExpectedStoreId -ExpectedFolderEntryId $ExpectedFolderId) -or
        [string]$Mail.Parent.EntryID -cne $ExpectedFolderId -or
        [string]$Mail.Parent.StoreID -cne $ExpectedStoreId -or
        [string]$Mail.Subject -cne [string]$Proof.ExpectedSubject) {
        throw 'BW2 synthetic MailItem/folder identity mismatch.'
    }
    $messageId=[string]$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if ($messageId -cne [string]$Proof.ExpectedInternetMessageId) {
        throw 'BW2 synthetic InternetMessageId differs from durable Intent.'
    }
    if ($Archive) {
        if ([string]$Mail.EntryID -cne [string]$Proof.ExpectedArchiveEntryId) {
            throw 'BW2 archive EntryID differs from LIVE6 claim.'
        }
        if ([long]$Proof.ApprovedArchiveSizeBytes -gt 0 -and
            [long]$Mail.Size -ne [long]$Proof.ApprovedArchiveSizeBytes) {
            throw 'BW2 archive size differs from manually approved LIVE6 claim.'
        }
    } elseif ([string]$Mail.EntryID -cne [string]$Proof.Request.SourceEntryId -or
        [long]$Mail.Size -ne [long]$Proof.ExpectedSizeBytes) {
        throw 'BW2 source MailItem differs from durable Intent.'
    }
    return $true
}
function Invoke-OPA265BW2ReadOnlySyntheticProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Payload)
    [void](Assert-OPA265BW2Payload -Payload $Payload)
    if ($PSVersionTable.PSEdition -cne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5 -or
        [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
        throw 'BW2 requires native Windows PowerShell 5.1 STA.'
    }
    $proof=Get-OPA265BW2FixtureProof -RunId ([string]$Payload.RunId) -SourcePst ([string]$Payload.SourcePst)
    if ([string]$proof.OperationId -cne [string]$Payload.OperationId -or
        [string]$proof.State -cne [string]$Payload.State -or
        [string]$proof.JournalSha256 -cne [string]$Payload.JournalSha256) {
        throw 'BW2 fixture changed between parent and child; no COM access.'
    }
    $app=$null;$ns=$null
    try {
        # Attach ONLY to already running Outlook; never new COM Outlook.
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        if ($null -eq $app) {throw 'BW2 requires already-running Outlook.'}
        $ns=$app.GetNamespace('MAPI')
        if ([string]$ns.CurrentProfileName -cne 'Outlook') {
            throw 'BW2 refuses profile other than approved TEST Outlook.'
        }
        $srcStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $proof.SourcePst
        $dstStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $proof.ArchivePst
        [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $srcStore)
        $req=$proof.Request
        if ([string]$srcStore.StoreID -cne [string]$req.SourceStoreId -or
            [string]$dstStore.StoreID -cne [string]$req.ArchiveStoreId) {
            throw 'BW2 source/archive StoreID mismatch.'
        }
        $src=$ns.GetFolderFromID([string]$req.SourceFolderEntryId,[string]$req.SourceStoreId)
        $dst=$ns.GetFolderFromID([string]$req.ArchiveFolderEntryId,[string]$req.ArchiveStoreId)
        if ($null -eq $src -or $null -eq $dst -or
            [string]$src.FolderPath -cne [string]$req.SourceFolderPath -or
            [string]$dst.FolderPath -cne [string]$req.ArchiveFolderPath -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$src.StoreID) -ObservedFolderEntryId ([string]$src.EntryID) -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderEntryId ([string]$req.SourceFolderEntryId)) -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$dst.StoreID) -ObservedFolderEntryId ([string]$dst.EntryID) -ExpectedStoreId ([string]$req.ArchiveStoreId) -ExpectedFolderEntryId ([string]$req.ArchiveFolderEntryId))) {
            throw 'BW2 exact synthetic folder identity mismatch.'
        }
        $sc=[int]$src.Items.Count;$dc=[int]$dst.Items.Count
        if ($sc -gt 1 -or $dc -gt 1) {throw 'BW2 refuses extra or duplicate items.'}
        $sm=0;$dm=0;$archiveId=''
        if ($sc -eq 1) {
            $mail=$src.Items.Item(1)
            [void](Assert-OPA265BW2MatchingMail -Mail $mail -Folder $src -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderId ([string]$req.SourceFolderEntryId) -Proof $proof)
            $sm=1
        }
        if ($dc -eq 1) {
            $mail=$dst.Items.Item(1)
            [void](Assert-OPA265BW2MatchingMail -Mail $mail -Folder $dst -ExpectedStoreId ([string]$req.ArchiveStoreId) -ExpectedFolderId ([string]$req.ArchiveFolderEntryId) -Proof $proof -Archive)
            $dm=1;$archiveId=[string]$mail.EntryID
        }
        $decision=Assert-OPA265BW2ObservedCounts -State ([string]$proof.State) -SourceCount $sc -ArchiveCount $dc -SourceMatches $sm -ArchiveMatches $dm
        if ([string]$proof.JournalSha256 -cne (Get-FileHash -LiteralPath $proof.Paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
            throw 'BW2 journal changed during Outlook observation.'
        }
        return [pscustomobject]@{
            Schema='2.6.5-BW2.SyntheticReadOnlyResult.1'
            RunId=[string]$proof.RunId
            OperationId=[string]$proof.OperationId
            State=[string]$proof.State
            Decision=$decision
            SourceItemCount=$sc
            ArchiveItemCount=$dc
            SyntheticSourceMatches=$sm
            SyntheticArchiveMatches=$dm
            ArchiveEntryId=$archiveId
            JournalSha256=[string]$proof.JournalSha256
            OutlookProfile='Outlook'
            OnlySyntheticFoldersInspected=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            AutomaticRetryAllowed=$false
            RealMailMoveViaWorker=$false
            ProductionReady=$false
        }
    } finally {
        if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
        }
        if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
        }
    }
}
