#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a4OneShotMovePolicy265.ps1')
    $script:suite='ec04df86-913a-49f7-9b5c-2cb626fa7b8c'
    $script:layout=Get-OPA265BW4k7v2a4Layout -SuiteId $script:suite -LocalAppData $env:LOCALAPPDATA
    $script:controller=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a4OneShotMove.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a4Scope {
        return @{
            Layout=$script:layout;ActualProfileName='Outlook'
            Accounts=@([pscustomobject]@{
                SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='POP3'
            })
            Stores=@(
                [pscustomobject]@{StoreId='DEFAULT';FilePath=''}
                [pscustomobject]@{StoreId='POP3';FilePath='C:\Dummy\info@stios.ru.pst'}
            )
            DefaultStoreId='DEFAULT'
        }
    }
    function New-BW4k7v2a4Manifest {
        return [pscustomobject]@{
            SuiteId=$script:suite;SourceEntryId='SRC';SourceStoreId='DEFAULT'
            TargetStoreId='NEW';TargetFolderId='FOLDER'
            SemanticSha256=('a'*64)
        }
    }
    function New-BW4k7v2a4Claim {
        return [pscustomobject]@{
            SuiteId=$script:suite;SourceEntryId='SRC';SourceStoreId='DEFAULT'
            TargetStoreId='NEW';TargetFolderId='FOLDER'
        }
    }
    function New-BW4k7v2a4Witness {
        return [pscustomobject]@{
            SemanticSha256=('a'*64);ParentStoreId='NEW';ParentFolderId='FOLDER'
        }
    }
    function New-BW4k7v2a4Recon {
        return @{
            Manifest=(New-BW4k7v2a4Manifest)
            Claim=(New-BW4k7v2a4Claim)
            SourceMatches=0;DestinationMatches=1
            DestinationWitnesses=@(New-BW4k7v2a4Witness)
            OutlookRestartConfirmed=$true
        }
    }
}
Describe 'BW4k7v2a4 ONE-shot synthetic default Drafts to disposable PST Move policy' {
    It 'new suite layout has a separate GUID-scoped test PST' {
        $script:layout.PstPath | Should -Match ([regex]::Escape($script:suite))
    }
    It 'never reuses historical failed BW4k7v2a1 SuiteId' {
        {Get-OPA265BW4k7v2a4Layout -SuiteId '2c15cb7c-4c09-4bcf-bca1-9fec458af3a5' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects old BW4k7v original forensic SuiteId' {
        {Get-OPA265BW4k7v2a4Layout -SuiteId '78a3e477-98fc-4134-b400-429b3e3b216b' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects non-canonical uppercase SuiteId' {
        {Get-OPA265BW4k7v2a4Layout -SuiteId $script:suite.ToUpperInvariant() -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects forged source or subject in test layout' {
        $copy=$script:layout.PSObject.Copy();$copy.Subject='wrong'
        {Assert-OPA265BW4k7v2a4Layout -Layout $copy -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'accepts current Outlook profile with one POP3 and separate default store' {
        $p=New-BW4k7v2a4Scope
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeTrue
    }
    It 'rejects default store equal to original POP3 delivery StoreID' {
        $p=New-BW4k7v2a4Scope;$p.DefaultStoreId='POP3'
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects other Outlook profiles' {
        $p=New-BW4k7v2a4Scope;$p.ActualProfileName='Unexpected'
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects IMAP rather than exact POP3 account' {
        $p=New-BW4k7v2a4Scope;$p.Accounts[0].AccountType=1
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects unknown default StoreID' {
        $p=New-BW4k7v2a4Scope;$p.DefaultStoreId='UNKNOWN'
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects duplicate default StoreIDs' {
        $p=New-BW4k7v2a4Scope
        $p.Stores+=([pscustomobject]@{StoreId='DEFAULT';FilePath=''})
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects missing POP3 delivery account' {
        $p=New-BW4k7v2a4Scope;$p.Accounts=@()
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'accepts exact separate target PST only when attached is expected' {
        $p=New-BW4k7v2a4Scope
        $p.Stores+=([pscustomobject]@{StoreId='NEW';FilePath=$script:layout.PstPath})
        (Test-OPA265BW4k7v2a4StoreScope @p -TargetAttached).Approved | Should -BeTrue
    }
    It 'rejects a target PST pre-attached before create' {
        $p=New-BW4k7v2a4Scope
        $p.Stores+=([pscustomobject]@{StoreId='NEW';FilePath=$script:layout.PstPath})
        (Test-OPA265BW4k7v2a4StoreScope @p).Approved | Should -BeFalse
    }
    It 'rejects target PST absent during review/move/reconcile' {
        $p=New-BW4k7v2a4Scope
        (Test-OPA265BW4k7v2a4StoreScope @p -TargetAttached).Approved | Should -BeFalse
    }
    It 'semantic witness matches synthetic mail class and content' {
        $w=Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';Body='Body';To='a@invalid';Unread=$false;Class=43
        })
        $w.SemanticSha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'semantic witness rejects nonmail object' {
        {Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';Body='Body';To='a@invalid';Unread=$false;Class=26
        })} | Should -Throw
    }
    It 'semantic witness rejects missing Body evidence' {
        {Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';To='a@invalid';Unread=$false;Class=43
        })} | Should -Throw
    }
    It 'semantic witness detects even one character changed' {
        $w1=Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';Body='Body';To='a@invalid';Unread=$false;Class=43
        })
        $w2=Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';Body='Bodx';To='a@invalid';Unread=$false;Class=43
        })
        $w1.SemanticSha256 | Should -Not -BeExactly $w2.SemanticSha256
    }
    It 'semantic witness cannot certify full production SEM-001 fields' {
        (Get-OPA265BW4k7v2a4SemanticWitness -Snapshot ([pscustomobject]@{
            Subject='Synthetic';Body='Body';To='a@invalid';Unread=$false;Class=43
        })).CompleteSEM001ProductionFieldsProven | Should -BeFalse
    }
    It 'reconcile accepts source zero target one content match only as manual SEM-001 review' {
        $p=New-BW4k7v2a4Recon
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'OneShotMoveReconciledSyntheticContentMatchSEM001ManualReview'
    }
    It 'reconcile detects source still contains exact pilot' {
        $p=New-BW4k7v2a4Recon;$p.SourceMatches=1
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile detects destination zero' {
        $p=New-BW4k7v2a4Recon;$p.DestinationMatches=0;$p.DestinationWitnesses=@()
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile detects duplicate destination subject' {
        $p=New-BW4k7v2a4Recon;$p.DestinationMatches=2
        $p.DestinationWitnesses=@(New-BW4k7v2a4Witness),(New-BW4k7v2a4Witness)
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile detects corrupted synthetic Body digest' {
        $p=New-BW4k7v2a4Recon
        $p.DestinationWitnesses[0].SemanticSha256=('f'*64)
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile detects wrong target store' {
        $p=New-BW4k7v2a4Recon
        $p.DestinationWitnesses[0].ParentStoreId='OTHER'
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile detects forged claim original SourceEntryID' {
        $p=New-BW4k7v2a4Recon;$p.Claim.SourceEntryId='DIFFERENT'
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile requires independent Outlook restart' {
        $p=New-BW4k7v2a4Recon;$p.OutlookRestartConfirmed=$false
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).Status |
            Should -BeExactly 'ManualReviewRequiredUnreconciled'
    }
    It 'reconcile never allows automatic Move retry' {
        $p=New-BW4k7v2a4Recon
        (Test-OPA265BW4k7v2a4MoveReconciliation @p).OriginalMoveMayBeRetried | Should -BeFalse
    }
    It 'reconcile never waives unknown MAPI flags or grants production readiness' {
        $p=New-BW4k7v2a4Recon
        $r=Test-OPA265BW4k7v2a4MoveReconciliation @p
        $r.SEM001RiskAcceptanceAutomaticallyGranted | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'controller has separate creation and Move consent paths' {
        $script:controller | Should -Match 'AllowDefaultDraftsSyntheticWrite'
        $script:controller | Should -Match 'ConfirmOneShotMove'
        $script:controller | Should -Match 'CREATE BW4K7V2A4 DRAFT'
        $script:controller | Should -Match 'MOVE BW4K7V2A4 ONCE'
    }
    It 'controller writes Move claim before exactly one COM Move invocation' {
        $claim=$script:controller.IndexOf('Write-OPA265BW4k7v2a1JsonOnce -Path $layout.MoveClaimPath')
        $move=$script:controller.IndexOf('$moved=$read.Move(')
        $claim | Should -BeGreaterThan 0
        $move | Should -BeGreaterThan $claim
        ([regex]::Matches($script:controller,'\$read\.Move\(')).Count | Should -Be 1
    }
    It 'controller records original source and destination identity before Move' {
        $script:controller | Should -Match 'SourceStoreId'
        $script:controller | Should -Match 'SourceEntryId'
        $script:controller | Should -Match 'TargetStoreId'
        $script:controller | Should -Match 'TargetFolderId'
    }
    It 'controller verifies exact pilot subject, old source and target with readback' {
        $script:controller | Should -Match 'GetItemFromID'
        $script:controller | Should -Match 'SubjectItems'
        $script:controller | Should -Match 'semantic witness changed'
    }
    It 'controller never touches historical BW4k7v2a1 fixture or automatic deletes' {
        $script:controller | Should -Not -Match '\.(Delete|Send|RemoveStore|RemoveStoreEx)\s*\('
        $script:controller | Should -Match 'never retry MovePilot'
    }
    It 'controller requires Outlook restart to reconcile and never calls second Move' {
        $script:controller | Should -Match 'Reconcile requires complete Outlook process restart'
        $script:controller | Should -Match 'NoSecondMoveOrSaveExecuted'
    }
    It 'controller reads raw PR_MESSAGE_FLAGS for analysis, not general waiver' {
        $script:controller | Should -Match '0x0E070003'
        $script:controller | Should -Match 'UnknownMapiFlagsAutomaticallyWaived=\$false'
    }
}