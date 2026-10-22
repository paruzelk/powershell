function Write-OPADiscoverySummary {
    param([Parameter(Mandatory=$true)][object]$Discovery)

    Write-Host ""
    Write-Host ("Accounts: {0}" -f @($Discovery.Accounts).Count)
    Write-Host ("Stores  : {0}" -f @($Discovery.Stores).Count)
    Write-Host ""
    Write-Host "Account protocol detection:"

    foreach ($a in @($Discovery.Accounts)) {
        Write-Host ("  {0} -> {1} (AccountType={2})" -f $a.UserName, $a.Protocol, $a.AccountType)
    }

    Write-Host ""
    Write-Host ("POP3 PST candidates: {0}" -f @($Discovery.Pop3Sources).Count)

    foreach ($s in @($Discovery.Pop3Sources)) {
        Write-Host ("  POP3: {0} -> {1}" -f $s.UserName, $s.FilePath)
    }
}