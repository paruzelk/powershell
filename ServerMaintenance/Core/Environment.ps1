function Get-SMFEnvironment {


    $os = Get-CimInstance Win32_OperatingSystem


    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    $isAdmin = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )


    return [PSCustomObject]@{

        ComputerName = $env:COMPUTERNAME

        OS = $os.Caption

        PowerShell = $PSVersionTable.PSVersion.ToString()

        Architecture = $os.OSArchitecture

        Admin = $isAdmin

    }


}