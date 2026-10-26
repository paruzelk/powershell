# Explicit controller API for single bounded worker operations.
# NO automatic retry: any outcome without a validated worker response requires
# independent reconciliation before future mail-mutating operations are added.
function Invoke-OPAWorkerControlledOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Ping','Echo','Fail','Crash','Delay','ProbeOutlook','ProbeSyntheticPstReadOnly','BW3SyntheticOneShotMove')][string]$Operation,
        [object]$Payload = @{},
        [ValidateRange(1,300)][int]$TimeoutSeconds = 15,
        [switch]$KeepArtifacts,
        [string]$RequestId = ''
    )
    return Invoke-OPAWorkerRequest -Operation $Operation -Payload $Payload -TimeoutSeconds $TimeoutSeconds -ReturnOutcome -KeepArtifacts:$KeepArtifacts -RequestId $RequestId
}

function Get-OPAWorkerRecoveryDisposition {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Succeeded','Failed','Indeterminate')][string]$Status)
    switch ($Status) {
        'Succeeded' { return 'Proceed' }
        'Failed' { return 'Stop' }
        'Indeterminate' { return 'ReconcileBeforeRetry' }
    }
}
