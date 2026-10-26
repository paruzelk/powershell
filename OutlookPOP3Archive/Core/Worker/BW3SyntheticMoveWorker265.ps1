#requires -Version 5.1
# BW3 Worker: ONE new LIVE3 synthetic test message, no retries.
function Invoke-OPA265BW3SyntheticOneShotMove {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Payload,
          [Parameter(Mandatory=$true)][string]$RequestId)
    [void](Assert-OPA265BW3Payload -Payload $Payload)
    if ([string]$Payload.WorkerRequestId -cne $RequestId) {
        throw 'BW3 request correlation failed before Outlook inspection.'
    }
    if ($PSVersionTable.PSEdition -cne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5 -or
        [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
        throw 'BW3 requires native Windows PowerShell 5.1 STA.'
    }
    $pre=Get-OPA265BW3Preflight -RunId ([string]$Payload.RunId) -SourcePst ([string]$Payload.SourcePst) -ExpectedJournalSha256 ([string]$Payload.JournalSha256) -ForDispatchedWorker
    if ([string]$pre.OperationId -cne [string]$Payload.OperationId) {
        throw 'BW3 durable operation differs from dispatched request.'
    }
    if (-not [IO.File]::Exists([string]$pre.Extra.DispatchClaimPath)) {
        throw 'BW3 durable parent dispatch claim must exist before Worker.'
    }
    $claim=Read-OPAWorkerJson -Path $pre.Extra.DispatchClaimPath
    [void](Assert-OPA265BW3DispatchClaim -Claim $claim -Preflight $pre -RequestId $RequestId)
    $app=$null;$ns=$null;$stage='Attach existing test Outlook'
    try {
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        if ($null -eq $app) {throw 'BW3 requires already-running Outlook.'}
        $ns=$app.GetNamespace('MAPI')
        if ([string]$ns.CurrentProfileName -cne 'Outlook') {
            throw 'BW3 refuses non-test Outlook profile.'
        }
        $stage='Check exact mounted synthetic PST stores and POP3 binding'
        $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $pre.SourcePst
        $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $pre.ArchivePst
        [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
        $req=$pre.Request
        if ([string]$src.StoreID -cne [string]$req.SourceStoreId -or
            [string]$dst.StoreID -cne [string]$req.ArchiveStoreId -or
            [string]$src.StoreID -ceq [string]$dst.StoreID) {
            throw 'BW3 mounted synthetic StoreID mismatch.'
        }
        $stage='Check exact synthetic folders and single source item'
        $from=$ns.GetFolderFromID([string]$req.SourceFolderEntryId,[string]$req.SourceStoreId)
        $to=$ns.GetFolderFromID([string]$req.ArchiveFolderEntryId,[string]$req.ArchiveStoreId)
        if ($null -eq $from -or $null -eq $to -or
            [string]$from.Name -cne [string]$pre.Paths.SourceFolderName -or
            [string]$to.Name -cne [string]$pre.Paths.ArchiveFolderName -or
            [string]$from.FolderPath -cne [string]$req.SourceFolderPath -or
            [string]$to.FolderPath -cne [string]$req.ArchiveFolderPath -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$from.StoreID) -ObservedFolderEntryId ([string]$from.EntryID) -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderEntryId ([string]$req.SourceFolderEntryId)) -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$to.StoreID) -ObservedFolderEntryId ([string]$to.EntryID) -ExpectedStoreId ([string]$req.ArchiveStoreId) -ExpectedFolderEntryId ([string]$req.ArchiveFolderEntryId)) -or
            [int]$from.Items.Count -ne 1 -or [int]$to.Items.Count -ne 0) {
            throw 'BW3 must see exact synthetic source=1 and archive=0.'
        }
        $stage='Check exact synthetic MailItem fingerprint and unchanged size'
        $mail=$ns.GetItemFromID([string]$req.SourceEntryId,[string]$req.SourceStoreId)
        if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
            [string]$mail.EntryID -cne [string]$req.SourceEntryId -or
            -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$mail.Parent.StoreID) -ObservedFolderEntryId ([string]$mail.Parent.EntryID) -ExpectedStoreId ([string]$req.SourceStoreId) -ExpectedFolderEntryId ([string]$req.SourceFolderEntryId)) -or
            [string]$mail.Subject -cne [string]$pre.Intent.Subject -or
            [string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F') -cne [string]$pre.Intent.InternetMessageId -or
            [long]$mail.Size -ne [long]$pre.IntentSizeBytes) {
            throw 'BW3 synthetic source fingerprint changed after durable Intent; stop.'
        }
        $stage='Recheck parent dispatch claim and journal SHA256'
        $again=Read-OPAWorkerJson -Path $pre.Extra.DispatchClaimPath
        [void](Assert-OPA265BW3DispatchClaim -Claim $again -Preflight $pre -RequestId $RequestId)
        if ((Get-FileHash -LiteralPath $pre.Paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$pre.JournalSha256) {
            throw 'BW3 journal changed between preflight and attempt.'
        }
        $stage='Durably claim the one and only Move attempt'
        $fs=$null
        try {
            $fs=[IO.FileStream]::new([string]$pre.Paths.ClaimPath,
                [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $bytes=[Text.Encoding]::UTF8.GetBytes(([string]$pre.OperationId+[char]10))
            $fs.Write($bytes,0,$bytes.Length)
            $fs.Flush($true)
        } finally {
            if ($null -ne $fs) {$fs.Dispose()}
        }
        # Once ClaimPath exists, every outcome including timeout is
        # indeterminate until independent read-only PST reconciliation.
        $stage='Perform one cross-PST synthetic MailItem.Move'
        $moved=$mail.Move($to)
        if ($null -eq $moved -or
            [string]::IsNullOrWhiteSpace([string]$moved.EntryID)) {
            throw 'BW3 Move returned without exact destination EntryID.'
        }
        return [pscustomobject]@{
            Schema='2.6.5-BW3.MoveReturned.1'
            RunId=[string]$pre.RunId
            OperationId=[string]$pre.OperationId
            JournalSha256=[string]$pre.JournalSha256
            DestinationEntryId=[string]$moved.EntryID
            MoveReturned=$true
            MovesAttempted=1
            JournalCompleted=$false
            AutomaticRetryAllowed=$false
            RequiresIndependentReconciliation=$true
            ProductionReady=$false
        }
    } catch {
        throw ('BW3 isolated Worker failed at [{0}]: {1}. Preserve claims; NO AUTO RETRY.' -f $stage,[string]$_.Exception.Message)
    } finally {
        if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
        }
        if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
        }
    }
}
