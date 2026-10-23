#requires -Version 5.1


function New-SMFContext
{

    param
    (
        [string]$RootPath,

        [hashtable]$Config,

        [object]$Environment
    )


    $Context = [PSCustomObject]@{


        RootPath = $RootPath


        Config = $Config


        Environment = $Environment


        Profile = $Config.Profile


        StartTime = Get-Date


        LogFile = $Global:SMFLogFile


        Results = @()



    }


    return $Context

}