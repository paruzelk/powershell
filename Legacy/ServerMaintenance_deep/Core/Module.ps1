#requires -Version 5.1


# =====================================
# Server Maintenance Framework
# Module Core
# =====================================



function Register-SMFModule
{

    param
    (
        [string]
        $Name,

        [string]
        $Path,

        [int]
        $Order,

        [string]
        $ExecuteFunction
    )


    return [PSCustomObject]@{

        Name =
            $Name


        Path =
            $Path


        Order =
            $Order


        ExecuteFunction =
            $ExecuteFunction


        Status =
            "Registered"

    }

}







function Test-SMFModuleContract
{

    param
    (
        [string]
        $Path,

        [string]
        $ModuleName
    )



    if (!(Test-Path $Path))
    {
        return $false
    }





    $Content =
        Get-Content `
            -Path $Path `
            -Raw





    $RequiredFunctions = @(

        "Get-SMFModuleInfo"

        "Invoke-$($ModuleName.Replace('-',''))"

    )







    foreach ($Function in $RequiredFunctions)
    {

        if ($Content -notmatch "function\s+(global:)?$Function")
        {

            return $false

        }

    }





    return $true

}