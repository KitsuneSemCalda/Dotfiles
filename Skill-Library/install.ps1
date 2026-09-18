#!/usr/bin/env pwsh
<#
install.ps1 - instala as skills da Skill-Library nos agentes CLI detectados
nesta maquina. Porta nativa em PowerShell do install.pl (usado no perfil
Omarchy/Linux), sem depender de Perl no Windows.

Uso:
  pwsh ./install.ps1                # instala todas as skills em todos os agentes detectados
  pwsh ./install.ps1 -Agent codex
  pwsh ./install.ps1 -List          # lista skills e agentes detectados
  pwsh ./install.ps1 -DryRun        # mostra o que seria instalado, sem copiar nada
#>

param(
    [string]$Agent = '',
    [switch]$DryRun,
    [switch]$List,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Output @'
Uso: pwsh install.ps1 [opcoes]

  -Agent <nome>  instala em apenas um agente (claude, codex, opencode)
  -List          lista as skills da biblioteca e os agentes detectados
  -DryRun        mostra o que seria instalado sem copiar nada
  -Help          mostra esta ajuda

Sem opcoes, cada skill em skills/ e copiada para o diretorio de skills de
cada agente CLI suportado detectado nesta maquina.
'@
    exit 0
}

$UserHome = $env:USERPROFILE
if (-not $UserHome) { $UserHome = $HOME }

$Agents = [ordered]@{
    claude   = Join-Path $UserHome '.claude\skills'
    codex    = Join-Path $UserHome '.codex\skills'
    opencode = Join-Path $UserHome '.config\opencode\skills'
}

$ScriptDir = $PSScriptRoot
$SkillsDir = Join-Path $ScriptDir 'skills'

function Get-LibrarySkills {
    if (-not (Test-Path -LiteralPath $SkillsDir)) { return @() }
    Get-ChildItem -LiteralPath $SkillsDir -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
        Sort-Object -Property Name |
        ForEach-Object { $_.Name }
}

$Skills = @(Get-LibrarySkills)

if ($List) {
    Write-Output 'Skills na biblioteca:'
    if ($Skills.Count -gt 0) {
        foreach ($skill in $Skills) { Write-Output "  - $skill" }
    } else {
        Write-Output '  (nenhuma ainda)'
    }
    Write-Output ''
    Write-Output 'Agentes detectados nesta maquina:'
    foreach ($name in $Agents.Keys) {
        $dest = $Agents[$name]
        $installed = Test-Path -LiteralPath (Split-Path -Path $dest -Parent)
        $suffix = if ($installed) { '' } else { ' (nao instalado, pulado)' }
        Write-Output "  - $name -> $dest$suffix"
    }
    exit 0
}

if ($Skills.Count -eq 0) {
    Write-Output 'Nenhuma skill encontrada em Skill-Library/skills - nada a instalar.'
    exit 0
}

$AgentNames = if ($Agent) { @($Agent) } else { @($Agents.Keys) }
foreach ($name in $AgentNames) {
    if (-not $Agents.Contains($name)) {
        throw "Agente desconhecido '$name'. Agentes conhecidos: $($Agents.Keys -join ', ')"
    }
}

$Targets = @($AgentNames | Where-Object { Test-Path -LiteralPath (Split-Path -Path $Agents[$_] -Parent) })

if ($Targets.Count -eq 0) {
    Write-Output 'Nenhum agente CLI suportado detectado nesta maquina (procurei .claude, .codex e .config/opencode). Nada instalado.'
    exit 0
}

foreach ($name in $Targets) {
    $target = $Agents[$name]
    foreach ($skill in $Skills) {
        $src = Join-Path $SkillsDir $skill
        $dest = Join-Path $target $skill
        if ($DryRun) {
            Write-Output "Instalaria $skill -> $dest"
            continue
        }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
        Write-Output "Instalado $skill -> $dest"
    }
}
