#!/usr/bin/env pwsh
<#
Coleta um perfil de hardware sanitizado (sem e-mail de proprietario, chave de
produto ou dados de rede) para decisoes de configuracao. Equivalente ao
scripts/hardware-profile.pl do perfil Omarchy, mas usando CIM em vez de inxi.

Sem acentos de proposito: Windows PowerShell 5.1 le .ps1 sem BOM como ANSI,
o que corrompe literais acentuados nesse ambiente.

Uso:
  pwsh ./scripts/hardware-profile.ps1            # mostra na tela
  pwsh ./scripts/hardware-profile.ps1 -Save      # grava em hardware/hardware-profile.txt
#>

param(
    [switch]$Save
)

$ErrorActionPreference = 'Stop'

function Get-BatteryHealth {
    try {
        $design = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop |
            Select-Object -First 1 -ExpandProperty DesignedCapacity
        $full = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop |
            Select-Object -First 1 -ExpandProperty FullChargedCapacity
        if ($design -and $full -and $design -gt 0) {
            $percent = [math]::Round(($full / $design) * 100, 1)
            return "$full mWh de $design mWh de projeto ($percent% da capacidade original)"
        }
    } catch {
        return 'Indisponivel (sem bateria ou WMI de bateria nao exposto)'
    }
    return 'Indisponivel'
}

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs  = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disks = Get-CimInstance Win32_DiskDrive
$os = Get-CimInstance Win32_OperatingSystem

$ramGiB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

$lines = @(
    "Fabricante/modelo : $($cs.Manufacturer) $($cs.Model)"
    "BIOS              : $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"
    "CPU               : $($cpu.Name.Trim()) ($($cpu.NumberOfCores) nucleos / $($cpu.NumberOfLogicalProcessors) threads)"
    "RAM               : $ramGiB GiB"
    "GPU               : $($gpu.Name) - $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
    "Sistema           : $($os.Caption) build $($os.BuildNumber)"
    "Bateria           : $(Get-BatteryHealth)"
)

foreach ($disk in $disks) {
    $sizeGiB = [math]::Round($disk.Size / 1GB, 1)
    $lines += "Disco             : $($disk.Model) ($sizeGiB GiB)"
}

$output = $lines -join "`n"
Write-Output $output

if ($Save) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $target = Join-Path $repoRoot 'hardware/hardware-profile.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Set-Content -Path $target -Value $output -Encoding utf8
    Write-Output "`nSalvo em: $target"
}
