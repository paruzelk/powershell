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
    $consentFields=@('ConfirmSourceSizeDifference','ExpectedSourceSizeBytes')
    $consentPresent=($fields -ccontains $consentFields[0] -or
        $fields -ccontains $consentFields[1])
    if ($consentPresent) {
        if ($fields.Count -ne 8 -or
            $fields -cnotcontains $consentFields[0] -or
            $fields -cnotcontains $consentFields[1] -or
            $Payload.ConfirmSourceSizeDifference -isnot [bool] -or
            -not [bool]$Payload.ConfirmSourceSizeDifference -or
            [string]$Payload.ExpectedSourceSizeBytes -cne '1808' -or
            [string]$Payload.State -cne 'UnresolvedIntent') {
            throw 'BW2c: unapproved or incomplete source-size consent payload.'
        }
    }
    if (($fields.Count -ne 6 -and -not $consentPresent) -or
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
# Pure diagnostic evidence only. Does not read, write, or change Outlook.
# SHA256 is calculated from the exact EntryID text to avoid printing IDs.
function Get-OPA265BW2SourceFingerprintEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ExpectedEntryId,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ObservedEntryId,
        [long]$IntentSizeBytes,
        [long]$ObservedSourceSizeBytes
    )
    if ([string]::IsNullOrWhiteSpace($ExpectedEntryId) -or
        [string]::IsNullOrWhiteSpace($ObservedEntryId) -or
        $IntentSizeBytes -lt 0 -or $ObservedSourceSizeBytes -lt 0) {
        throw 'BW2b source fingerprint requires nonempty EntryIDs and nonnegative sizes.'
    }
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try {
        $expectedHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($ExpectedEntryId)))).Replace('-','').ToLowerInvariant()
        $observedHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($ObservedEntryId)))).Replace('-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    $entryMatches=[string]::Equals($ExpectedEntryId,$ObservedEntryId,[StringComparison]::Ordinal)
    $sizeMatches=($IntentSizeBytes -eq $ObservedSourceSizeBytes)
    return [pscustomobject]@{
        Schema='2.6.5-BW2b.SourceFingerprintEvidence.1'
        SourceEntryIdMatchesIntent=$entryMatches
        ExpectedSourceEntryIdSha256=$expectedHash
        ObservedSourceEntryIdSha256=$observedHash
        IntentSizeBytes=$IntentSizeBytes
        ObservedSourceSizeBytes=$ObservedSourceSizeBytes
        SizeDifferenceBytes=($ObservedSourceSizeBytes - $IntentSizeBytes)
        SourceSizeMatchesIntent=$sizeMatches
        ExactMatch=($entryMatches -and $sizeMatches)
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
    }
}
function Assert-OPA265BW2SourceFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence)
    if ([string]$Evidence.Schema -cne '2.6.5-BW2b.SourceFingerprintEvidence.1' -or
        [bool]$Evidence.AutomaticRetryAllowed -or
        [bool]$Evidence.OutlookMoveExecuted -or
        -not [bool]$Evidence.ExactMatch) {
        $format = 'BW2b source fingerprint mismatch (NO AUTO RETRY): ' +
            'SourceEntryIdMatchesIntent={0}; SourceSizeMatchesIntent={1}; ' +
            'IntentSizeBytes={2}; ObservedSourceSizeBytes={3}; SizeDifferenceBytes={4}; ' +
            'ExpectedSourceEntryIdSha256={5}; ObservedSourceEntryIdSha256={6}'
        throw ($format -f
            [bool]$Evidence.SourceEntryIdMatchesIntent,
            [bool]$Evidence.SourceSizeMatchesIntent,
            [long]$Evidence.IntentSizeBytes,
            [long]$Evidence.ObservedSourceSizeBytes,
            [long]$Evidence.SizeDifferenceBytes,
            [string]$Evidence.ExpectedSourceEntryIdSha256,
            [string]$Evidence.ObservedSourceEntryIdSha256)
    }
    return $true
}
# BW2c strictly single-fixture manual read-only consent. This does NOT
# authorize any MailItem.Move or permanent correction of durable Intent.
function Assert-OPA265BW2SourceSizeConsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][object]$Proof,
          [Parameter(Mandatory=$true)][object]$Consent)
    if ([string]$Proof.RunId -cne '77854a93-ecfd-42c7-b58e-2948fe9afa88' -or
        [string]$Proof.OperationId -cne 'e249f73b-8cdf-4672-92e3-5c49f8feaca0' -or
        [string]$Proof.State -cne 'UnresolvedIntent' -or
        [string]$Proof.JournalSha256 -cne '22d2047972825f3207ef3b099f57ebe46d6088a5f4c7fd0525ab45dd19d098fc' -or
        [long]$Proof.ExpectedSizeBytes -ne 1436 -or
        [string]$Evidence.Schema -cne '2.6.5-BW2b.SourceFingerprintEvidence.1' -or
        -not [bool]$Evidence.SourceEntryIdMatchesIntent -or
        [bool]$Evidence.SourceSizeMatchesIntent -or
        [bool]$Evidence.AutomaticRetryAllowed -or
        [bool]$Evidence.OutlookMoveExecuted -or
        -not [bool]$Consent.ConfirmSourceSizeDifference -or
        [long]$Consent.ExpectedSourceSizeBytes -ne 1808 -or
        [long]$Evidence.ObservedSourceSizeBytes -ne [long]$Consent.ExpectedSourceSizeBytes -or
        [long]$Evidence.SizeDifferenceBytes -ne 372) {
        throw 'BW2c: explicit size consent rejected (exact RunId/OperationId/Intent SHA, EntryID and pinned observed bytes required); NO AUTO RETRY.'
    }
    return $true
}
function Assert-OPA265BW2MatchingMail {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,[Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][string]$ExpectedStoreId,
          [Parameter(Mandatory=$true)][string]$ExpectedFolderId,
          [Parameter(Mandatory=$true)][object]$Proof,[switch]$Archive,
          [object]$SourceSizeConsent=$null)
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
    } else {
        # Keep the exact original invariant. BW2b exposes BOTH components of
        # a mismatch; it never treats MAPI size drift as automatic consent.
        $evidence=Get-OPA265BW2SourceFingerprintEvidence `
            -ExpectedEntryId ([string]$Proof.Request.SourceEntryId) `
            -ObservedEntryId ([string]$Mail.EntryID) `
            -IntentSizeBytes ([long]$Proof.ExpectedSizeBytes) `
            -ObservedSourceSizeBytes ([long]$Mail.Size)
        if ($null -ne $SourceSizeConsent) {
            [void](Assert-OPA265BW2SourceSizeConsent -Evidence $evidence -Proof $Proof -Consent $SourceSizeConsent)
        } else {
            [void](Assert-OPA265BW2SourceFingerprint -Evidence $evidence)
        }
        return $evidence
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
    $consent=$null
    if ($Payload.PSObject.Properties.Name -ccontains 'ConfirmSourceSizeDifference') {
        $consent=$Payload
        # Reject unsolicited consent before any Outlook COM access.
        if ([string]$proof.State -cne 'UnresolvedIntent' -or
            [string]$proof.RunId -cne '77854a93-ecfd-42c7-b58e-2948fe9afa88' -or
            [string]$proof.OperationId -cne 'e249f73b-8cdf-4672-92e3-5c49f8feaca0' -or
            [string]$proof.JournalSha256 -cne '22d2047972825f3207ef3b099f57ebe46d6088a5f4c7fd0525ab45dd19d098fc' -or
            [long]$proof.ExpectedSizeBytes -ne 1436) {
            throw 'BW2c: explicit source-size consent outside exact synthetic fixture.'
        }
    }
    if ([string]$proof.OperationId -cne [string]$Payload.OperationId -or
        [string]$proof.State -cne [string]$Payload.State -or
        [string]$proof.JournalSha256 -cne [string]$Payload.JournalSha256) {
        throw 'BW2 fixture changed between parent and child; no COM access.'
    }
    $app=$null;$ns=$null
    $stage='Attach existing Outlook'
    try {
        # Attach ONLY to already running Outlook; never new COM Outlook.
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        if ($null -eq $app) {throw 'BW2 requires already-running Outlook.'}
        $ns=$app.GetNamespace('MAPI')
        if ([string]$ns.CurrentProfileName -cne 'Outlook') {
            throw 'BW2 refuses profile other than approved TEST Outlook.'
        }
        $stage='Check exact mounted stores and POP3 binding'
        $srcStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $proof.SourcePst
        $dstStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $proof.ArchivePst
        [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $srcStore)
        $req=$proof.Request
        if ([string]$srcStore.StoreID -cne [string]$req.SourceStoreId -or
            [string]$dstStore.StoreID -cne [string]$req.ArchiveStoreId) {
            throw 'BW2 source/archive StoreID mismatch.'
        }
        $stage='Check synthetic folder entry IDs and paths'
        $src=$ns.GetFolderFromID([string]$req.SourceFolderEntryId,[string]$req.SourceStoreId)
        $dst=$ns.GetFolderFromID([string]$req.ArchiveFolderEntryId,[string]$req.ArchiveStoreId)
        if ($null -eq $src -or $null -eq $dst -or
            [string]$src.FolderPath -cne [string]$req.SourceFolderPath -or
            [string]$dst.FolderPath -cne [string]$req.ArchiveFolderPath -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$src.StoreID) -ObservedFolderEntryId ([string]$src.EntryID) -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderEntryId ([string]$req.SourceFolderEntryId)) -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$dst.StoreID) -ObservedFolderEntryId ([string]$dst.EntryID) -ExpectedStoreId ([string]$req.ArchiveStoreId) -ExpectedFolderEntryId ([string]$req.ArchiveFolderEntryId))) {
            throw 'BW2 exact synthetic folder identity mismatch.'
        }
        $stage='Check exact synthetic item counts'
        $sc=[int]$src.Items.Count;$dc=[int]$dst.Items.Count
        if ($sc -gt 1 -or $dc -gt 1) {throw 'BW2 refuses extra or duplicate items.'}
        $stage='Check unique synthetic MailItem identity'
        $sm=0;$dm=0;$archiveId='';$sourceEvidence=$null
        if ($sc -eq 1) {
            $mail=$src.Items.Item(1)
            $sourceEvidence=Assert-OPA265BW2MatchingMail -Mail $mail -Folder $src -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderId ([string]$req.SourceFolderEntryId) -Proof $proof -SourceSizeConsent $consent
            $sm=1
        }
        if ($dc -eq 1) {
            $mail=$dst.Items.Item(1)
            [void](Assert-OPA265BW2MatchingMail -Mail $mail -Folder $dst -ExpectedStoreId ([string]$req.ArchiveStoreId) -ExpectedFolderId ([string]$req.ArchiveFolderEntryId) -Proof $proof -Archive)
            $dm=1;$archiveId=[string]$mail.EntryID
        }
        $stage='Classify exact synthetic source/target contents'
        $decision=Assert-OPA265BW2ObservedCounts -State ([string]$proof.State) -SourceCount $sc -ArchiveCount $dc -SourceMatches $sm -ArchiveMatches $dm
        $stage='Recheck unchanged journal SHA256'
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
            SourceSizeDifferenceExplicitlyApproved=([bool]($null -ne $consent -and
                $null -ne $sourceEvidence -and -not [bool]$sourceEvidence.SourceSizeMatchesIntent))
            SourceEntryIdMatchesIntent=$(if ($null -eq $sourceEvidence) {$false} else {[bool]$sourceEvidence.SourceEntryIdMatchesIntent})
            SourceSizeMatchesIntent=$(if ($null -eq $sourceEvidence) {$false} else {[bool]$sourceEvidence.SourceSizeMatchesIntent})
            IntentSizeBytes=[long]$proof.ExpectedSizeBytes
            ObservedSourceSizeBytes=$(if ($null -eq $sourceEvidence) {0} else {[long]$sourceEvidence.ObservedSourceSizeBytes})
            SizeDifferenceBytes=$(if ($null -eq $sourceEvidence) {0} else {[long]$sourceEvidence.SizeDifferenceBytes})
            JournalSha256=[string]$proof.JournalSha256
            OutlookProfile='Outlook'
            OnlySyntheticFoldersInspected=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            AutomaticRetryAllowed=$false
            RealMailMoveViaWorker=$false
            ProductionReady=$false
        }
    } catch {
        throw ('BW2 read-only stage [{0}]: {1}' -f $stage,[string]$_.Exception.Message)
    } finally {
        if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
        }
        if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
        }
    }
}
