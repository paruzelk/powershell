#requires -Version 5.1

# =====================================
# Server Maintenance Framework
# Module Loader
# =====================================

function Import-SMFModules
{
    param
    (
        [string]$ModulesPath,
        [hashtable]$Config,
        [string]$Profile
    )

    $LoadedModules = New-Object System.Collections.ArrayList

    foreach ($ModuleName in $Config.Modules.Keys)
    {
        Write-Host ""
        Write-Host "Checking:"
        Write-Host "  $ModuleName"

        $ModuleConfig = $Config.Modules[$ModuleName]
        if ($null -eq $ModuleConfig) { continue }

        Write-Host "  Config: FOUND"

        if (-not $ModuleConfig.Enabled)
        {
            Write-Host "  Enabled: False"
            continue
        }

        Write-Host "  Enabled: True"

        if ($ModuleConfig.Profiles -notcontains $Profile)
        {
            Write-Host "  Current profile: $Profile"
            Write-Host "  Profile: SKIP"
            continue
        }

        Write-Host "  Current profile: $Profile"
        Write-Host "  Profile: OK"

        $ModuleFile = Join-Path $ModulesPath "$ModuleName.ps1"

        if (-not (Test-Path $ModuleFile))
        {
            Write-Host "  Module file missing"
            if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
            {
                Write-SMFLog "Module file missing: $ModuleFile"
            }
            continue
        }

        $Contract = Test-SMFModuleContract -Path $ModuleFile -ModuleName $ModuleName

        if (-not $Contract)
        {
            Write-Host "  Contract: FAILED"
            if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
            {
                Write-SMFLog "Module contract failed: $ModuleName"
            }
            continue
        }

        Write-Host "  Contract: OK"

        . $ModuleFile

        $FunctionName = "Invoke-" + ($ModuleName -replace "-", "")

        if (-not (Get-Command $FunctionName -ErrorAction SilentlyContinue))
        {
            Write-Host "  Function not found"
            if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
            {
                Write-SMFLog "Function not found: $FunctionName"
            }
            continue
        }

        Write-Host "  Function loaded globally: $FunctionName"

        $Module = Register-SMFModule -Name $ModuleName -Path $ModuleFile -Order $ModuleConfig.Order -ExecuteFunction $FunctionName

        Write-Host "  Registered: YES"

        [void]$LoadedModules.Add($Module)

        if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
        {
            Write-SMFLog "Registered module: $ModuleName"
        }
    }

    return $LoadedModules | Sort-Object Order
}

function Invoke-SMFModules
{
    param
    (
        [object]$Context,
        [array]$Modules
    )

    foreach ($Module in $Modules)
    {
        Write-Host ""
        Write-Host "Executing:"
        Write-Host "  $($Module.Name)"
        Write-Host "  Function:"
        Write-Host "  $($Module.ExecuteFunction)"

        if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
        {
            Write-SMFLog "Executing module: $($Module.Name)"
        }

        $Command = Get-Command $Module.ExecuteFunction -ErrorAction SilentlyContinue

        if ($null -eq $Command)
        {
            Write-Host ""
            Write-Host "  ERROR:"
            Write-Host "Function $($Module.ExecuteFunction) not found"
            if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
            {
                Write-SMFLog "Function not found: $($Module.ExecuteFunction)"
            }
            continue
        }

        try
        {
            $Output = @( & $Command.Name -Context $Context )

            foreach ($Item in $Output)
            {
                if ($Item -is [pscustomobject] -and $Item.PSObject.Properties["Module"])
                {
                    [void]$Context.Results.Add($Item)
                    if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
                    {
                        Write-SMFLog "Module finished: $($Item.Module) ($($Item.Status))"
                    }
                }
                else
                {
                    Write-Host "  WARNING: Ignored output without 'Module' property: $($Item.GetType().Name)"
                }
            }
        }
        catch
        {
            Write-Host ""
            Write-Host "  ERROR:"
            Write-Host $_.Exception.Message
            if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue)
            {
                Write-SMFLog "Exception in module $($Module.Name): $($_.Exception.Message)"
            }
        }
    }
}