#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Runtime/PesterReleaseGate.ps1')
    function New-OPA263FakePesterRun {
        [pscustomobject]@{
            Result='Passed'; Executed=$true
            Containers=@([pscustomobject]@{Name='One.Tests.ps1';Result='Passed'},[pscustomobject]@{Name='Two.Tests.ps1';Result='Passed'})
            TotalCount=2; PassedCount=2; FailedCount=0; SkippedCount=0
            InconclusiveCount=0; NotRunCount=0
            FailedBlocksCount=0; FailedContainersCount=0
        }
    }
}
Describe '2.6.3 mandatory Pester release gate' {
    It 'accepts only a fully passed run with all expected containers' {
        $r=Assert-OPAPesterReleaseGate -Result (New-OPA263FakePesterRun) -ExpectedContainerCount 2
        $r.PassedCount | Should -Be 2
        $r.ContainerCount | Should -Be 2
    }
    It 'rejects a failed discovery container with zero failed tests (original 2.6.3 regression)' {
        $r=New-OPA263FakePesterRun
        $r.FailedContainersCount=1
        $r.Result='Failed'
        $r.Containers[1].Result='Failed'
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*failed-containers=1*'
    }
    It 'rejects failed discovery even if the Pester top-level status incorrectly says Passed' {
        $r=New-OPA263FakePesterRun
        $r.FailedContainersCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*failed-containers=1*'
    }
    It 'rejects failed BeforeAll blocks with zero failed It tests' {
        $r=New-OPA263FakePesterRun
        $r.FailedBlocksCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*failed-blocks=1*'
    }
    It 'rejects a missing container even when all discovered tests passed' {
        $r=New-OPA263FakePesterRun
        $r.Containers=@($r.Containers[0])
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*containers=1/2*'
    }
    It 'rejects a container whose own status is failed despite a passed summary' {
        $r=New-OPA263FakePesterRun
        $r.Containers[1].Result='Failed'
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*container*Failed*'
    }
    It 'rejects a missing Pester result property (fail closed)' {
        $r=New-OPA263FakePesterRun
        $r.PSObject.Properties.Remove('FailedContainersCount')
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*required result field*'
    }
    It 'rejects one failed It test' {
        $r=New-OPA263FakePesterRun
        $r.PassedCount=1
        $r.FailedCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*failed=1*'
    }
    It 'rejects skipped tests' {
        $r=New-OPA263FakePesterRun
        $r.PassedCount=1
        $r.SkippedCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*skipped=1*'
    }
    It 'rejects inconclusive and not-run tests' {
        $r=New-OPA263FakePesterRun
        $r.PassedCount=1
        $r.InconclusiveCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*inconclusive=1*'
        $r.InconclusiveCount=0
        $r.NotRunCount=1
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*not-run=1*'
    }
    It 'rejects a Pester run that was never executed' {
        $r=New-OPA263FakePesterRun
        $r.Executed=$false
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*executed=False*'
    }
    It 'rejects an internally inconsistent total count' {
        $r=New-OPA263FakePesterRun
        $r.TotalCount=3
        { Assert-OPAPesterReleaseGate -Result $r -ExpectedContainerCount 2 } | Should -Throw '*Pester release gate FAILED*'
    }
}
