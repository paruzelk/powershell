#requires -Version 5.1
# Pester test failures, discovery errors, failed setup blocks, and incomplete
# test inventories all block a release. PassedCount alone is not sufficient.
function Assert-OPAPesterReleaseGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][ValidateRange(1,100000)][int]$ExpectedContainerCount
    )

    $required = @(
        'Result','Executed','Containers','TotalCount','PassedCount','FailedCount',
        'SkippedCount','InconclusiveCount','NotRunCount',
        'FailedBlocksCount','FailedContainersCount'
    )
    foreach ($field in $required) {
        if ($Result.PSObject.Properties.Name -notcontains $field) {
            throw ("Pester release gate: required result field '{0}' is missing." -f $field)
        }
    }

    if ($null -eq $Result.Containers) {
        throw 'Pester release gate: container inventory is null.'
    }
    $containers = [int]$Result.Containers.Count
    $passed = [int]$Result.PassedCount
    $failed = [int]$Result.FailedCount
    $skipped = [int]$Result.SkippedCount
    $inconclusive = [int]$Result.InconclusiveCount
    $notRun = [int]$Result.NotRunCount
    $failedBlocks = [int]$Result.FailedBlocksCount
    $failedContainers = [int]$Result.FailedContainersCount
    $total = [int]$Result.TotalCount
    $summary = ("result={0}; executed={1}; containers={2}/{3}; passed={4}; failed={5}; skipped={6}; inconclusive={7}; not-run={8}; failed-blocks={9}; failed-containers={10}" -f
        [string]$Result.Result,[bool]$Result.Executed,$containers,$ExpectedContainerCount,
        $passed,$failed,$skipped,$inconclusive,$notRun,$failedBlocks,$failedContainers)

    if ([string]$Result.Result -cne 'Passed' -or
        -not [bool]$Result.Executed -or
        $containers -ne $ExpectedContainerCount -or
        $passed -le 0 -or
        $failed -gt 0 -or $skipped -gt 0 -or
        $inconclusive -gt 0 -or $notRun -gt 0 -or
        $failedBlocks -gt 0 -or $failedContainers -gt 0 -or
        $total -ne ($passed + $failed + $skipped + $inconclusive + $notRun)) {
        throw ("Pester release gate FAILED: {0}" -f $summary)
    }
    foreach ($container in $Result.Containers) {
        if ([string]$container.Result -cne 'Passed') {
            throw ("Pester release gate FAILED: test container '{0}' has status '{1}'." -f
                [string]$container.Name,[string]$container.Result)
        }
    }
    return [pscustomobject]@{
        PassedCount=$passed
        ContainerCount=$containers
        Summary=$summary
    }
}
