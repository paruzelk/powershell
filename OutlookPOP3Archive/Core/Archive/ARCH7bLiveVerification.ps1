#requires -Version 5.1
# ARCH7b bounded DEV live-Outlook verification. No Outlook shutdown or activation.
function Get-OPAARCH7bWorkerIdentity {
    [CmdletBinding()]
    param()
    $p=[Diagnostics.Process]::GetCurrentProcess()
    try{
        [pscustomobject]@{Id=[int]$p.Id;StartUtcTicks=[long]$p.StartTime.ToUniversalTime().Ticks;SessionId=[int]$p.SessionId}
    }finally{$p.Dispose()}
}
function Assert-OPAARCH7bOutlookIdentity {
    param([Parameter(Mandatory=$true)][object]$Pending,
          [Parameter(Mandatory=$true)][object]$Outlook)
    if([int]$Pending.MoveProcessId -le 0 -or [long]$Pending.MoveProcessStartUtcTicks -le 0 -or
       [int]$Outlook.Id -ne [int]$Pending.MoveProcessId -or [long]$Outlook.StartUtcTicks -ne [long]$Pending.MoveProcessStartUtcTicks){
        throw 'ARCH7b Outlook process identity changed; preserve pending, never restart Outlook.'
    }
}
function Test-OPAARCH7bMoveWorkerAlive {
    param([int]$ProcessId,[long]$StartUtcTicks)
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if($null -eq $p){return $false}
    try{return ([long]$p.StartTime.ToUniversalTime().Ticks -eq $StartUtcTicks)}
    finally{$p.Dispose()}
}
function Assert-OPAARCH7bLiveFence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pending,
          [Parameter(Mandatory=$true)][object]$Outlook,
          [Parameter(Mandatory=$true)][object]$Worker)
    foreach($name in @('VerificationPolicy','MoveWorkerId','MoveWorkerStartUtcTicks','MoveWorkerSessionId')){
        if($Pending.PSObject.Properties.Name -notcontains $name){throw 'ARCH7b pending has no live verification identity.'}
    }
    if($Pending.VerificationPolicy -cne 'ARCH7bFreshWorkerSameOutlook' -or [int]$Pending.MoveWorkerId -le 0 -or
       [long]$Pending.MoveWorkerStartUtcTicks -le 0 -or [int]$Pending.MoveWorkerSessionId -lt 0){
        throw 'ARCH7b invalid live verification pending identity.'
    }
    Assert-OPAARCH7bOutlookIdentity -Pending $Pending -Outlook $Outlook
    if([int]$Worker.Id -le 0 -or [int]$Worker.Id -eq [int]$Pending.MoveWorkerId -or
       [long]$Worker.StartUtcTicks -le [long]$Pending.MoveWorkerStartUtcTicks -or
       [int]$Worker.SessionId -ne [int]$Pending.MoveWorkerSessionId){
        throw 'ARCH7b requires a new PowerShell worker in the original session.'
    }
    if(Test-OPAARCH7bMoveWorkerAlive -ProcessId ([int]$Pending.MoveWorkerId) -StartUtcTicks ([long]$Pending.MoveWorkerStartUtcTicks)){
        throw 'ARCH7b original Move worker still running; wait for its exit.'
    }
}
function Assert-OPAARCH7bPendingPolicy {
    param([Parameter(Mandatory=$true)][object]$Pending,[switch]$ConfirmLiveOutlookVerification)
    $tagged=$Pending.PSObject.Properties.Name -contains 'VerificationPolicy'
    if($tagged -and $Pending.VerificationPolicy -cne 'ARCH7bFreshWorkerSameOutlook'){
        throw 'ARCH7b unknown pending verification policy.'
    }
    if([bool]$tagged -ne [bool]$ConfirmLiveOutlookVerification){
        throw 'ARCH7b pending verification policy mismatch; use original mode.'
    }
}
