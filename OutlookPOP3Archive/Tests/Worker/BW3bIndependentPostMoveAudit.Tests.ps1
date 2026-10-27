#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
}
Describe 'BW3b one historical synthetic post-Move read-only evidence audit' {
    BeforeEach {
        $script:p=Get-OPA265BW3bPinnedIdentity
        $script:proof=[pscustomobject]@{
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            JournalSha256=$script:p.JournalSha256
            SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
            Intent=[pscustomobject]@{Size=1436;Subject=('OPA264 LIVE3 synthetic '+$script:p.RunId);
                InternetMessageId=('<opa264-live3-'+$script:p.RunId+'@example.invalid>')}
            Request=[pscustomobject]@{
                ArchiveStoreId='ARCHIVE-STORE-1'
                ArchiveFolderEntryId='ARCHIVE-FOLDER-1'
                ArchiveFolderPath='\\SyntheticArchive'
            }
        }
        $script:dispatch=[pscustomobject]@{
            Schema='2.6.5-BW3.DispatchClaim.1'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            JournalSha256=$script:p.JournalSha256
            SourcePst=$script:proof.SourcePst
            Utc='2026-10-27T00:00:00.0000000Z'
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            JournalCompleted=$false
            PstReconciliationComplete=$false
        }
        $script:report=[pscustomobject]@{
            Schema='2.6.5-BW3.ControllerResult.1'
            Status='MoveReturnedNeedsIndependentReview'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            WorkerProcessId=5296
            WorkerStatus='Succeeded'
            FailureKind='None'
            Error=''
            DestinationEntryId=$script:p.ArchiveEntryId
            JournalSha256=$script:p.JournalSha256
            DispatchClaimExists=$true
            MoveAttemptClaimExists=$true
            WorkerMoveMayHaveExecuted=$true
            JournalCompleted=$false
            AutomaticRetryAllowed=$false
            RequiresIndependentReconciliation=$true
            ProductionReady=$false
            NextAction='StopAndPerformIndependentReadOnlyReview'
        }
        $script:claim=[string]$script:p.OperationId+[char]10
        $script:observed=[pscustomobject]@{
            RunId=$script:p.RunId
            SourceItemCount=0
            ArchiveItemCount=1
            SyntheticSourceMatches=0
            SyntheticArchiveMatches=1
            ArchiveEntryId=$script:p.ArchiveEntryId
            ArchiveStoreId=$script:proof.Request.ArchiveStoreId
            ArchiveFolderEntryId=$script:proof.Request.ArchiveFolderEntryId
            ArchiveFolderPath=$script:proof.Request.ArchiveFolderPath
            InternetMessageId=$script:proof.Intent.InternetMessageId
            Subject=$script:proof.Intent.Subject
            MailClass=43
            ObservedArchiveSizeBytes=1444
            OnlySyntheticFoldersInspected=$true
        }
    }
    It 'accepts all four correlated durable identity components' {
        (Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects unapproved RunId' {
        $script:proof.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects unapproved OperationId' {
        $script:proof.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects altered original journal SHA' {
        $script:proof.JournalSha256='b'*64
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a fabricated alternate pinned identity' {
        $script:p.ArchiveEntryId='FABRICATED-ENTRY'
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a missing dispatch claim field' {
        $script:dispatch.PSObject.Properties.Remove('WorkerRequestId')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects an unexpected dispatch claim field' {
        $script:dispatch | Add-Member NoteProperty RetryAllowed $true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a missing controller record field' {
        $script:report.PSObject.Properties.Remove('WorkerProcessId')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects an extra controller record field' {
        $script:report | Add-Member NoteProperty AutoReconcile $true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign WorkerRequestId in dispatch' {
        $script:dispatch.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign WorkerRequestId in controller result' {
        $script:report.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects an attempt claim belonging to a different operation' {
        $script:claim=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects missing attempt claim contents' {
        $script:claim=''
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign destination EntryID in controller' {
        $script:report.DestinationEntryId='DIFFERENT-ENTRY'
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects successful status with Worker-reported failure' {
        $script:report.WorkerStatus='Failed'
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects controller report with a nonempty Error' {
        $script:report.Error='Failure'
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects zero child PID in controller report' {
        $script:report.WorkerProcessId=0
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects controller claiming journal completion' {
        $script:report.JournalCompleted=$true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects dispatcher allowing automatic retry' {
        $script:dispatch.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects dispatcher claiming PST reconciliation' {
        $script:dispatch.PstReconciliationComplete=$true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'rejects forged production-ready controller' {
        $script:report.ProductionReady=$true
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'requires original post-Move classification with independent review' {
        $script:report.RequiresIndependentReconciliation=$false
        { Assert-OPA265BW3bRecords -Proof $script:proof -Dispatch $script:dispatch -Report $script:report -MoveClaimText $script:claim -Pinned $script:p } | Should -Throw
    }
    It 'accepts exact archive EntryID and synthetic fingerprint evidence' {
        (Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects an archive EntryID differing from COM result' {
        $script:observed.ArchiveEntryId='BAD-ENTRY'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong archive StoreID' {
        $script:observed.ArchiveStoreId='WRONG-PST'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong archive folder EntryID' {
        $script:observed.ArchiveFolderEntryId='WRONG-FOLDER'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong archive FolderPath' {
        $script:observed.ArchiveFolderPath='\\WrongArchive'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects altered message InternetMessageId' {
        $script:observed.InternetMessageId='<foreign@example.invalid>'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects altered synthetic subject' {
        $script:observed.Subject='Normal user Inbox mail'
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects more than one archive item' {
        $script:observed.ArchiveItemCount=2
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects source item still present' {
        $script:observed.SourceItemCount=1
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects missing archived item' {
        $script:observed.ArchiveItemCount=0
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects a non-MailItem object' {
        $script:observed.MailClass=26
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects empty or negative archive message size' {
        $script:observed.ObservedArchiveSizeBytes=0
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'rejects insufficient synthetic-only scope proof' {
        $script:observed.OnlySyntheticFoldersInspected=$false
        { Assert-OPA265BW3bMailboxEvidence -Observed $script:observed -Proof $script:proof -Pinned $script:p } | Should -Throw
    }
    It 'returns read-only identity confirmation without approving archive size drift' {
        $v=Get-OPA265BW3bVerdict -Proof $script:proof -Pinned $script:p -Observed $script:observed
        $v.Status | Should -Be 'IndependentPostMoveAuditPassed'
        $v.Decision | Should -Be 'MoveConfirmedByEntryIdAndSyntheticIdentity'
        $v.ArchiveEntryIdMatchesWorker | Should -BeTrue
        $v.IntentSizeBytes | Should -Be 1436
        $v.ObservedArchiveSizeBytes | Should -Be 1444
        $v.ArchiveSizeDifferenceBytes | Should -Be 8
        $v.ArchiveSizeMatchesIntent | Should -BeFalse
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
        $v.RequiresManualSizeReview | Should -BeTrue
        $v.ContentByteEqualityVerified | Should -BeFalse
        $v.JournalChanged | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'returns no manual size review only when observed size matches Intent' {
        $script:observed.ObservedArchiveSizeBytes=1436
        $v=Get-OPA265BW3bVerdict -Proof $script:proof -Pinned $script:p -Observed $script:observed
        $v.ArchiveSizeMatchesIntent | Should -BeTrue
        $v.RequiresManualSizeReview | Should -BeFalse
        $v.ContentByteEqualityVerified | Should -BeFalse
    }
    It 'never infers that matching archive size proves byte equality' {
        $script:observed.ObservedArchiveSizeBytes=1436
        $v=Get-OPA265BW3bVerdict -Proof $script:proof -Pinned $script:p -Observed $script:observed
        $v.ContentByteEqualityVerified | Should -BeFalse
        $v.JournalCompleted | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
    }
    It 'keeps the standalone audit strictly read-only: no Move Save Delete or store mount' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3bIndependentMoveAudit.ps1') -Raw
        $s | Should -Not -Match '[$]mail[.]Move[(]|[$]mail[.]Save[(]|AddStoreEx[(]|RemoveStore[(]|Write-OPAOperationJournalEvent|Write-OPA264Live6ReconciledLocked'
        $s | Should -Not -Match 'New-Object -ComObject|[$]app[.]Quit[(]|Stop-Process'
    }
    It 'checks pinned journal hash both before and after COM read-only inspection' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3bIndependentMoveAudit.ps1') -Raw
        ([regex]::Matches($s,'Get-FileHash -LiteralPath [$]paths[.]JournalPath')).Count | Should -Be 2
    }
    It 'rechecks exact raw dispatch, controller and attempt evidence after inspection' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3bIndependentMoveAudit.ps1') -Raw
        $s | Should -Match '[$]dispatchRaw'
        $s | Should -Match '[$]reportRaw'
        $s | Should -Match '[$]attempt'
    }
    It 'does not import or modify default Archive/Resume production path' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $s | Should -Not -Match 'BW3bIndependent'
    }
    It 'has no PowerShell AST parsing errors in the new protocol and inspector' {
        foreach($name in @('Core/Worker/BW3bIndependentAudit265.ps1','Core/Diagnostics/Test-OPA265BW3bIndependentMoveAudit.ps1')) {
            $tokens=$null;$errors=$null
            $file=Join-Path (Join-Path $PSScriptRoot '../..') $name
            $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
