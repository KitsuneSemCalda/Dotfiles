#!/usr/bin/env pwsh
<#
debloat.ps1 - remocao conservadora de bloatware + limpeza, especifico para
esta instalacao (lista construida a partir do "Get-AppxPackage" real desta
maquina, nao uma lista generica baixada da internet).

Sem acentos de proposito: Windows PowerShell 5.1 le .ps1 sem BOM como ANSI,
o que corrompe literais acentuados neste ambiente.

O que este script NAO faz, de proposito:
  - Nao mexe no Windows Defender nem no Windows Update.
  - Nao remove OneDrive, Edge, WSL, Dev Home nem apps claramente instalados
    de proposito (Claude, ChatGPT Desktop, Dropbox, Spotify, VSCode).
  - Nao mexe nos apps da Samsung (SamsungSettings/SamsungSecurity/etc.) -
    em notebooks OEM isso costuma controlar hardware de verdade (backlight
    do teclado, limite de carga da bateria).
  - Nao mexe em pacotes com nome estranho/GUID (ex.: as strings aleatorias
    tipo "MicrosoftWindows.60719890.Voiess") - parecem experimentos
    internos de shell/taskbar/fala e o risco de quebrar algo nao vale a
    pena so' por "limpeza".
  - Nao mexe em servicos do Windows nem em politicas de grupo/registro de
    telemetria via servico - so desliga tarefas agendadas, que sao 100%
    reversiveis com Enable-ScheduledTask.
  - Nao troca o plano de energia.

Uso:
  pwsh ./scripts/debloat.ps1              # so' mostra o que seria feito
  pwsh ./scripts/debloat.ps1 -Apply       # remove/desativa de verdade
#>

param(
    [switch]$Apply
)

$DryRun = -not $Apply

function Write-Action {
    param([string]$Tag, [string]$Message)
    Write-Output ("{0,-9}{1}" -f $Tag, $Message)
}

function Get-Tag {
    param([string]$DryTag, [string]$LiveTag)
    if ($DryRun) { return $DryTag }
    return $LiveTag
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Desativar as tarefas agendadas abaixo exige administrador (elas pertencem
# ao SYSTEM). Sem elevar, Disable-ScheduledTask falha com "Acesso negado" e
# isso tem que aparecer como falha, nao como sucesso silencioso.
if ($Apply -and -not $isAdmin) {
    Write-Output 'Elevando para administrador (necessario para desativar tarefas agendadas do sistema)...'
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"", '-Apply') -Verb RunAs -Wait
    exit 0
}

# Lista construida a partir do "Get-AppxPackage" real desta maquina (nao e'
# uma lista generica). So' bloat sem uso funcional pra este perfil (dev +
# jogos via Steam/PrismLauncher): editores/paywall de video, jogos com ads,
# apps de suporte raramente usados, cliente Teams de consumidor e o
# assistente Copilot (o usuario ja usa Claude/ChatGPT de proposito).
$BloatPackages = @(
    'Clipchamp.Clipchamp'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.GetHelp'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.OutlookForWindows'
    'MSTeams'
    'Microsoft.Copilot'
    'MicrosoftCorporationII.MicrosoftFamily'
)

# Tarefas agendadas de telemetria/diagnostico conhecidas e documentadas.
# Desligar (nao apagar) e' 100% reversivel com Enable-ScheduledTask.
$TelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)

function Remove-Bloatware {
    foreach ($name in $BloatPackages) {
        $installed = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
        if (-not $installed) {
            Write-Action 'OK' "$name (ja ausente)"
            continue
        }

        Write-Action (Get-Tag 'REMOVE?' 'REMOVE') $name
        if ($DryRun) { continue }

        $installed | Remove-AppxPackage -ErrorAction SilentlyContinue

        if ($isAdmin) {
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $name } |
                ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
        }
    }

    if (-not $isAdmin) {
        Write-Warning 'Sem privilegio de administrador: removi so para o usuario atual. Rode como administrador para tambem tirar do perfil provisionado (evita voltar em contas novas).'
    }
}

function Disable-TelemetryTasks {
    foreach ($path in $TelemetryTasks) {
        $taskPath = Split-Path $path -Parent
        $taskName = Split-Path $path -Leaf
        $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskPath\" -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Action 'OK' "$path (nao existe nesta instalacao)"
            continue
        }
        if ($task.State -eq 'Disabled') {
            Write-Action 'OK' "$path (ja desativada)"
            continue
        }

        Write-Action (Get-Tag 'DISABLE?' 'DISABLE') $path
        if (-not $DryRun) {
            try {
                Disable-ScheduledTask -TaskName $taskName -TaskPath "$taskPath\" -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "Falha ao desativar $path : $_"
            }
        }
    }
}

function Enable-StorageSense {
    $regPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    Write-Action (Get-Tag 'STORAGE?' 'STORAGE') 'Storage Sense (limpeza automatica de temporarios)'
    if ($DryRun) { return }

    New-Item -Path $regPath -Force | Out-Null
    New-ItemProperty -Path $regPath -Name '01' -Value 1 -PropertyType DWord -Force | Out-Null
}

function Clear-TempFiles {
    $targets = @($env:TEMP, 'C:\Windows\Temp')
    $before = 0
    foreach ($dir in $targets) {
        if (Test-Path -LiteralPath $dir) {
            $before += (Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
    }
    $beforeMiB = [math]::Round($before / 1MB, 1)

    Write-Action (Get-Tag 'CLEAN?' 'CLEAN') "Temporarios + Lixeira (~$beforeMiB MiB candidatos)"
    if ($DryRun) { return }

    foreach ($dir in $targets) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}

Remove-Bloatware
Disable-TelemetryTasks
Enable-StorageSense
Clear-TempFiles

Write-Output $(if ($DryRun) { "Dry-run concluido. Rode com -Apply para aplicar de verdade." } else { 'Debloat/otimizacao aplicados.' })
