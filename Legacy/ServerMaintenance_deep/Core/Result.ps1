#requires -Version 5.1


# =====================================
# Server Maintenance Framework
# Result Engine
# =====================================



function New-SMFResult
{

    param
    (
        [string]
        $ModuleName
    )



    return [PSCustomObject]@{


        Module =
            $ModuleName



        Status =
            "Started"



        StartTime =
            Get-Date



        EndTime =
            $null



        Duration =
            $null





        #
        # File statistics
        #

        FilesFound =
            0



        FilesProcessed =
            0



        FilesDeleted =
            0



        FilesSkipped =
            0






        #
        # Directory statistics
        #

        DirectoriesScanned =
            0






        #
        # Size statistics
        #

        BytesBefore =
            0



        BytesFreed =
            0






        #
        # Messages
        #

        Errors =
            @()



        Warnings =
            @()



        Details =
            @()



    }

}







function Complete-SMFResult
{

    param
    (
        [PSCustomObject]
        $Result,


        [string]
        $Status = "Completed"
    )



    $Result.Status =
        $Status



    $Result.EndTime =
        Get-Date



    $Result.Duration =
        $Result.EndTime -
        $Result.StartTime



}








function Add-SMFResultDetail
{

    param
    (
        [PSCustomObject]
        $Result,


        [string]
        $Message
    )



    $Result.Details +=
        $Message


}








function Add-SMFResultWarning
{

    param
    (
        [PSCustomObject]
        $Result,


        [string]
        $Message
    )



    $Result.Warnings +=
        $Message


}








function Add-SMFResultError
{

    param
    (
        [PSCustomObject]
        $Result,


        [string]
        $Message
    )



    $Result.Errors +=
        $Message


}