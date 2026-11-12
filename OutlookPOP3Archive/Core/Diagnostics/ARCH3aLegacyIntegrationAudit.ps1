#requires -Version 5.1
# ARCH3a: NON-MUTATING contract audit of the existing OutlookPOP3Archive
# implementation. No new archive routing algorithm; no Outlook or PST access.
# Always preserve the original ARCH2c4a/ARCH2d/ARCH2d5 evidence.
function Get-OPA265ARCH3aModuleInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    $names=[ordered]@{
        Main='OutlookPOP3Archive.ps1'
        Grouping='Core/Archive/ArchiveGrouping.ps1'
        Planner='Core/Archive/ArchivePlanner.ps1'
        Selector='Core/Archive/ArchiveSelector.ps1'
        SystemFolders='Core/Archive/SystemFolders.ps1'
        MailMover='Core/Archive/MailMover.ps1'
        Transaction='Core/Archive/ArchiveTransaction.ps1'
        StepJournal='Core/Archive/ArchiveTransaction.ps1'
        OperationJournal='Core/Archive/OperationJournal.ps1'
        DuplicateIndex='Core/Archive/DuplicateIndex.ps1'
        Verifier='Core/Archive/ArchiveVerifier.ps1'
        SemanticWitness='Core/Archive/ARCH2bSemanticWitness.ps1'
        LegacyFence='Core/Archive/ARCH2aMoveOutcomeFence.ps1'
        HundredPilot='Core/Archive/ARCH2d5Batch100Core.ps1'
        HundredPolicy='Core/Archive/ARCH2d5Batch100Policy.ps1'
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($key in @($names.Keys)){
        $relative=[string]$names[$key]
        $path=Join-Path $root $relative
        $exists=[IO.File]::Exists($path)
        $sha=''
        if($exists){
            if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw ('ARCH3a symbolic-link module refused: '+$relative)
            }
            $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        }
        $rows.Add([pscustomobject][ordered]@{
            Role=[string]$key
            RelativePath=$relative
            Exists=$exists
            CurrentSha256=$sha
        })|Out-Null
    }
    return @($rows.ToArray())
}

function Test-OPA265ARCH3aCapabilities {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    $required=[ordered]@{
        Main='OutlookPOP3Archive.ps1'
        Grouping='Core/Archive/ArchiveGrouping.ps1'
        Planner='Core/Archive/ArchivePlanner.ps1'
        Selector='Core/Archive/ArchiveSelector.ps1'
        SystemFolders='Core/Archive/SystemFolders.ps1'
        MailMover='Core/Archive/MailMover.ps1'
        Transaction='Core/Archive/ArchiveTransaction.ps1'
        OperationJournal='Core/Archive/OperationJournal.ps1'
        DuplicateIndex='Core/Archive/DuplicateIndex.ps1'
        Verifier='Core/Archive/ArchiveVerifier.ps1'
        SemanticWitness='Core/Archive/ARCH2bSemanticWitness.ps1'
        LegacyFence='Core/Archive/ARCH2aMoveOutcomeFence.ps1'
        HundredPilot='Core/Archive/ARCH2d5Batch100Core.ps1'
        HundredPolicy='Core/Archive/ARCH2d5Batch100Policy.ps1'
    }
    $source=@{}
    foreach($k in @($required.Keys)){
        $path=Join-Path $root ([string]$required[$k])
        if(-not [IO.File]::Exists($path)){throw ('ARCH3a baseline module missing: '+$required[$k])}
        if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw ('ARCH3a source module is reparse point: '+$required[$k])
        }
        $source[$k]=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    }
    # Static source check is a contract/provenance audit only, not proof that
    # Outlook/PST or fault-recovery would succeed in actual runtime.
    $rules=@(
        [pscustomobject]@{Code='SRC-GROUP-YEAR';Area='Archive grouping';Role='Grouping';
            Pattern="function Get-OPAArchiveGroupParts|ValidateSet\('None','Year','YearQuarter','YearMonth'\)";
            Requirement='Get-OPAArchiveGroupParts';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-ARCHIVE-NAME';Area='PST part naming';Role='MailMover';
            Pattern='function Get-OPAArchivePartPath';Requirement='Get-OPAArchivePartPath';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-ARCHIVE-DEST';Area='Year and rollover routing';Role='MailMover';
            Pattern='function Get-OPAArchiveDestination';Requirement='Get-OPAArchiveDestination';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-FOLDER-RECURSION';Area='POP3 recursive folder scope';Role='Planner';
            Pattern='function Get-OPAEligiblePop3MailFolders';Requirement='Get-OPAEligiblePop3MailFolders';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-OUTBOX-EXCLUSION';Area='Outbox exclusion';Role='SystemFolders';
            Pattern='function Test-OPAExcludedSystemFolder';Requirement='Test-OPAExcludedSystemFolder';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-SENT-DATE';Area='SentOn preference';Role='Selector';
            Pattern='function Get-OPAArchiveItemDate';Requirement='Get-OPAArchiveItemDate';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-MULTISTORE-SCOPE';Area='Canonical POP3 store source';Role='Main';
            Pattern='function Get-OPAPop3SourceFolders';Requirement='Get-OPAPop3SourceFolders';Disposition='Reuse'},
        [pscustomobject]@{Code='SRC-DUPLICATE-INDEX';Area='Duplicate detection';Role='DuplicateIndex';
            Pattern='function Test-OPADuplicateEntry';Requirement='Test-OPADuplicateEntry';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-STEP-JOURNAL';Area='Transaction step journal';Role='Transaction';
            Pattern='function Save-OPAArchiveTransaction';Requirement='Save-OPAArchiveTransaction';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-OP-JOURNAL';Area='Per-item operation journal';Role='OperationJournal';
            Pattern='function Write-OPAOperationJournalEvent';Requirement='Write-OPAOperationJournalEvent';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-BODY-WITNESS';Area='Original semantic witness';Role='MailMover';
            Pattern='Get-OPA265ARCH2bMailSemanticWitness -Mail \$item';Requirement='Get-OPA265ARCH2bMailSemanticWitness';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-VERIFY-ORIGINAL';Area='Semantic content comparison';Role='Verifier';
            Pattern='Compare-OPA265ARCH2bMailSemanticWitness';Requirement='Compare-OPA265ARCH2bMailSemanticWitness';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-VERIFY-CALLER';Area='Main uses semantic verification';Role='Main';
            Pattern='-ExpectedMoves \$expectedMoves -RequireSemanticWitness';Requirement='-RequireSemanticWitness';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-MOVE-PATH';Area='Existing COM MailMover';Role='MailMover';
            Pattern='\$moved = \$item\.Move\(\$dest\.Folder\)';Requirement='Move-OPAItemsWithLimit';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-ARCH2-100';Area='Bounded proven 100-mail Move';Role='HundredPilot';
            Pattern='\$moved=\$mail\.Move\(\$target\)';Requirement='ARCH2d5 one-shot';Disposition='Integrate'},
        [pscustomobject]@{Code='SRC-ARCH2-CHAIN';Area='Linked 100-mail evidence';Role='HundredPolicy';
            Pattern='function Read-OPA265ARCH2d5FullChain';Requirement='ARCH2d5 SHA receipt chain';Disposition='Integrate'},
        [pscustomobject]@{Code='SAFETY-WRITER-BLOCK';Area='Production writer safety';Role='Main';
            Pattern='Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode';Requirement='Writer remains blocked';Disposition='Preserve'},
        [pscustomobject]@{Code='SAFETY-BLOCK-CODE';Area='Archive/Resume/Auto block';Role='LegacyFence';
            Pattern="'Archive','Resume','Auto'";Requirement='Archive Resume Auto remain closed';Disposition='Preserve'}
    )
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($r in $rules){
        $present=([regex]::IsMatch([string]$source[$r.Role],[string]$r.Pattern))
        $rows.Add([pscustomobject][ordered]@{
            Code=$r.Code
            Area=$r.Area
            ExistingModule=[string]$required[$r.Role]
            Requirement=$r.Requirement
            PresentInExistingSource=$present
            Disposition=$r.Disposition
            EvidenceKind='StaticSourceMarkersOnly'
        })|Out-Null
    }
    return @($rows.ToArray())
}

function Get-OPA265ARCH3aIntegrationAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    $inventory=@(Get-OPA265ARCH3aModuleInventory -ProjectRoot $ProjectRoot)
    $capabilities=@(Test-OPA265ARCH3aCapabilities -ProjectRoot $ProjectRoot)
    $notFound=@($capabilities|Where-Object {-not $_.PresentInExistingSource})
    $gaps=@(
        [pscustomobject]@{Code='ARCH3B-CLAIM-CONTRACT';Module='MailMover.ps1 + ArchiveTransaction.ps1';Required='Map one original transaction operation to durable per-item one-shot claim and receipt with pre-PST creation intent';Solved=$false},
        [pscustomobject]@{Code='ARCH3C-RECEIPT-LINK';Module='OperationJournal.ps1 + DuplicateIndex.ps1';Required='Original source witness, archive destination, per-item claim/receipt and index share independently anchored IDs/hashes';Solved=$false},
        [pscustomobject]@{Code='ARCH3C-UNKNOWN-OUTCOME';Module='Move-OPAItemsWithLimit + Resume';Required='No automatic replay of COM-indeterminate original; independent classifying of changed source EntryID/provider status';Solved=$false},
        [pscustomobject]@{Code='ARCH3D-RESTART-RECONCILE';Module='ArchiveVerifier.ps1';Required='Independent post-Outlook-restart full semantic check across year/part/archive path and folder topology';Solved=$false},
        [pscustomobject]@{Code='ARCH3E-CASE-MATRIX';Module='Existing year/Sent/custom folder pipeline';Required='Real isolated-PST scenarios covering folder routing, multiple years, existing PST parts, faults and interruptions';Solved=$false},
        [pscustomobject]@{Code='ARCH3F-BIG-PST';Module='Whole archive runtime';Required='90 GB long-running, resource, provider and resume reliability tests before production';Solved=$false}
    )
    $allPresent=($notFound.Count -eq 0)
    $gatePresent=(@($capabilities|Where-Object{$_.Code -ceq 'SAFETY-WRITER-BLOCK' -and $_.PresentInExistingSource}).Count -eq 1 -and
        @($capabilities|Where-Object{$_.Code -ceq 'SAFETY-BLOCK-CODE' -and $_.PresentInExistingSource}).Count -eq 1)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3a.LegacyIntegrationAudit.1'
        Status=if($allPresent -and $gatePresent){'LegacyPipelineReuseConfirmedProductionIntegrationStillBlocked'}else{'LegacyPipelineContractMismatchManualReview'}
        ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
        LegacyFunctionalityMustBeReused=$true
        ExistingMoverWillNotBeReplaced=$true
        ExistingYearGroupingRetained=$true
        ExistingPop3FolderTraversalRetained=$true
        ModuleInventory=$inventory
        CapabilityChecks=$capabilities
        RequiredChecks=$capabilities.Count
        ChecksPresent=@($capabilities|Where-Object{$_.PresentInExistingSource}).Count
        MissingChecks=@($notFound|ForEach-Object{$_.Code})
        IntegrationGaps=$gaps
        OpenIntegrationGaps=$gaps.Count
        SourceMarkerEvidenceIsNotRuntimeCertification=$true
        OutlookContacted=$false
        ExistingPstOpened=$false
        JsonOrPstFilesWritten=$false
        HistoricARCH2d5ClaimTouched=$false
        AutomaticResumeOrMoveRetryAllowed=$false
        ArchiveResumeAutoRemainClosed=$true
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Get-OPA265ARCH3aExistingRoutingExamples {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot,
          [Parameter(Mandatory=$true)][string]$SourcePst)
    $root=[IO.Path]::GetFullPath($ProjectRoot)
    if([IO.Path]::GetFileName($SourcePst) -cne 'info@stios.ru.pst'){
        throw 'ARCH3a routing-contract examples require canonical POP3 source basename.'
    }
    # Dot-source EXISTING functions; do not duplicate the Year/Date logic.
    # Import contains only function definitions and script variables: no COM
    # objects constructed, no PST opened/attached or created.
    . (Join-Path $root 'Core/Archive/ArchiveGrouping.ps1')
    . (Join-Path $root 'Core/Archive/ArchiveSelector.ps1')
    . (Join-Path $root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $root 'Core/Archive/MailMover.ps1')
    $inboxDate=[datetime]'2020-02-12T12:30:00'
    $sentMail=[pscustomobject]@{
        ReceivedTime=[datetime]'2021-01-05T18:00:00'
        SentOn=[datetime]'2020-12-31T23:50:00'
        CreationTime=[datetime]'2020-12-31T23:51:00'
    }
    $sentDate=Get-OPAArchiveItemDate -Item $sentMail -PreferSentOn
    $archive2020=Get-OPAArchivePartPath -SourcePst $SourcePst -Year 2020 -Part 1
    $archive2021=Get-OPAArchivePartPath -SourcePst $SourcePst -Year 2021 -Part 1
    $inboxTarget=Get-OPAArchiveTargetPath -ReceivedTime $inboxDate -SourceFolderName 'Входящие' -SourceFolderPath '\\POP3 Store\Входящие' -Grouping Year
    $nestedTarget=Get-OPAArchiveTargetPath -ReceivedTime $inboxDate -SourceFolderName 'Договоры' -SourceFolderPath '\\POP3 Store\Проекты\Договоры' -Grouping Year
    $sentTarget=Get-OPAArchiveTargetPath -ReceivedTime $sentDate -SourceFolderName 'Отправленные' -SourceFolderPath '\\POP3 Store\Отправленные' -Grouping Year
    $map=@{KNOWN_SENT='SentMail';KNOWN_DRAFTS='Drafts';KNOWN_OUTBOX='Outbox'}
    $outboxExcluded=Test-OPAExcludedSystemFolder -Name 'Исходящие' -EntryID 'KNOWN_OUTBOX' -WellKnownEntryIdMap $map
    $sentExcluded=Test-OPAExcludedSystemFolder -Name 'Отправленные' -EntryID 'KNOWN_SENT' -WellKnownEntryIdMap $map
    $userDraftsExcluded=Test-OPAExcludedSystemFolder -Name 'Drafts' -EntryID 'USER_CUSTOM_DRAFTS' -WellKnownEntryIdMap $map
    $systemDraftsExcluded=Test-OPAExcludedSystemFolder -Name 'Drafts' -EntryID 'KNOWN_DRAFTS' -WellKnownEntryIdMap $map
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3a.OriginalRoutingExamples.1'
        Status='ExistingOriginalFunctionsExecutedWithoutComOrPstWrites'
        SourcePstBaseName=[IO.Path]::GetFileName($SourcePst)
        Archive2020Pst=$archive2020
        Archive2021Pst=$archive2021
        Archive2020And2021AreSeparate=($archive2020 -cne $archive2021)
        ExistingArchiveNamingUsed=$true
        ArchiveGrouping='Year'
        Inbox2020Folder=$inboxTarget
        Nested2020Folder=$nestedTarget
        SentUsesSentOnYear=$sentDate.Year
        Sent2020Folder=$sentTarget
        OutboxExcluded=[bool]$outboxExcluded
        SystemSentExcluded=[bool]$sentExcluded
        SystemDraftsExcluded=[bool]$systemDraftsExcluded
        UserDefinedDraftsExcluded=[bool]$userDraftsExcluded
        OriginalGroupingFunctionUsed=$true
        OriginalArchivePartPathFunctionUsed=$true
        OriginalSystemFolderClassifierUsed=$true
        OutlookContacted=$false
        ExistingPstOpened=$false
        JsonOrPstFilesWritten=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
