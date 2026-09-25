# ServerMaintenance

PowerShell 5.1 server maintenance framework.

## Supported platforms

- Windows Server 2016
- Windows Server 2019
- Windows Server 2022
- Windows Server 2025
- Windows 10+ for supported workstation-side testing

## Entry point

`Start-SMF.ps1`

## Modes / profiles

The project supports Analyze, Day and Night maintenance workflows, including preview analysis and HTML reporting.

## Modules

The project uses a modular cleanup architecture. Existing modules include:

- Clear-IISLogs
- Clear-WER
- Test-Module
- Clear-YandexCache
- Clear-EdgeCache
- Clear-WindowsLogs
- Clear-Temp

Status: development.