#requires -Version 5.1


# =====================================
# Server Maintenance Framework
# Test Module
# =====================================



function global:Get-SMFModuleInfo
{

    return [PSCustomObject]@{

        Name =
            "Test-Module"


        Version =
            "1.0.0"


        Description =
            "SMF test execution module"


    }

}








function global:Invoke-TestModule
{

    param
    (
        $Context
    )



    Write-Host ""

    Write-Host "Context profile test:"

    Write-Host "Profile:"
    Write-Host $Context.Profile



    Write-Host ""

    Write-Host "Profile settings:"

    $Context.ProfileSettings |
        Format-List





    Write-Host ""

    Write-Host "Config test:"

    Write-Host "Temp MaxAgeDays:"

    Write-Host `
        $Context.Config.Settings.Temp.MaxAgeDays



    Write-Host ""

    Write-Host "Network paths:"

    Write-Host `
        $Context.Config.Settings.Temp.IncludeNetworkPaths





    Write-Host ""



    $Result =
        New-SMFResult `
            "Test-Module"





    $Result.FilesFound =
        100



    $Result.FilesProcessed =
        100



    $Result.FilesDeleted =
        10



    $Result.BytesBefore =
        524288000



    $Result.BytesFreed =
        52428800





    Complete-SMFResult `
        $Result

    return $Result

}