#!/usr/bin/env pwsh
<#
dotfiles.ps1 - instalador/orquestrador dos dotfiles Windows-11.
Equivalente em espirito ao omarchy.pl do perfil Omarchy: por padrao nao
altera nada quando ha conflito, cria symlinks para os arquivos de
configuracao simples e usa flags separadas para as acoes que mexem em
sistema (fontes, tema, apps).

Sem acentos de proposito nas strings/comentarios: Windows PowerShell 5.1 le
.ps1 sem BOM como ANSI, o que corrompe literais acentuados neste ambiente.

Uso:
  pwsh ./dotfiles.ps1 -DryRun              # mostra o que seria feito
  pwsh ./dotfiles.ps1 -Backup              # symlinks, preservando conflitos
  pwsh ./dotfiles.ps1 -Restore             # restaura o backup mais recente
  pwsh ./dotfiles.ps1 -Fonts               # instala Lexend + JetBrainsMono Nerd Font
  pwsh ./dotfiles.ps1 -Theme               # aplica color scheme + wallpaper SAO
  pwsh ./dotfiles.ps1 -Apps                # winget install das ferramentas usadas
  pwsh ./dotfiles.ps1 -All -Backup         # tudo de uma vez

Criar symlinks no Windows sem ser administrador exige o "Modo de
desenvolvedor" ativado (Config. > Privacidade e seguranca > Para
desenvolvedores).
#>

param(
    [switch]$DryRun,
    [switch]$Backup,
    [switch]$Restore,
    [switch]$Fonts,
    [switch]$Theme,
    [switch]$Apps,
    [switch]$All,
    [string]$Target = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

if ($All) {
    $Fonts = $true
    $Theme = $true
    $Apps = $true
}

if ($Restore -and ($Backup -or $Fonts -or $Theme -or $Apps)) {
    throw '-Restore nao pode ser combinado com -Backup, -Fonts, -Theme, -Apps ou -All'
}

$RealHome = $env:USERPROFILE
if (($Fonts -or $Theme -or $Apps) -and $Target -ne $RealHome) {
    throw '-Fonts, -Theme e -Apps so podem usar o HOME real; use -Target apenas para testar symlinks'
}

$RepoRoot = $PSScriptRoot
$SourceRoot = Join-Path $RepoRoot 'home'
$BackupBase = Join-Path $Target '.local\state\dotfiles\backups'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = Join-Path $BackupBase $Stamp

function Write-Action {
    param([string]$Tag, [string]$Message)
    Write-Output ("{0,-8}{1}" -f $Tag, $Message)
}

# Helper em vez do operador ternario `?:`, que so existe no PowerShell 7+
# (este script tambem precisa rodar em Windows PowerShell 5.1).
function Get-Tag {
    param([string]$DryTag, [string]$LiveTag)
    if ($DryRun) { return $DryTag }
    return $LiveTag
}

# $PROFILE resolve para o perfil do host que esta rodando este script
# (PowerShell 5.1 ou 7). Quando -Target difere do HOME real (uso de teste),
# reprojeta esse caminho sob $Target em vez de tocar no profile de verdade.
function Get-ProfileDestination {
    if ($Target -eq $RealHome) { return $PROFILE }
    if ($PROFILE.StartsWith($RealHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $PROFILE.Substring($RealHome.Length).TrimStart('\')
        return Join-Path $Target $relative
    }
    return $PROFILE
}

# Mapa: caminho relativo dentro de home/ -> destino real no Windows.
function Get-LinkMap {
    @(
        @{ Source = 'glazewm\config.yaml'; Destination = (Join-Path $Target '.glzr\glazewm\config.yaml') }
        @{ Source = 'starship.toml'; Destination = (Join-Path $Target '.config\starship.toml') }
        @{ Source = 'powershell\Microsoft.PowerShell_profile.ps1'; Destination = (Get-ProfileDestination) }
        @{ Source = 'rainmeter\AincradHUD'; Destination = (Join-Path $Target 'Documents\Rainmeter\Skins\AincradHUD') }
    )
}

function Test-PointsToSource {
    param([string]$Destination, [string]$Source)
    $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) { return $false }
    $linkTarget = $item.Target | Select-Object -First 1
    if (-not $linkTarget) { return $false }
    return (Resolve-Path -LiteralPath $linkTarget -ErrorAction SilentlyContinue).Path -eq (Resolve-Path -LiteralPath $Source).Path
}

function Install-Symlinks {
    $failures = 0
    foreach ($entry in Get-LinkMap) {
        $source = Join-Path $SourceRoot $entry.Source
        $destination = $entry.Destination
        $relative = $entry.Source

        if (-not (Test-Path -LiteralPath $source)) {
            Write-Warning "Origem ausente: $source"
            $failures++
            continue
        }

        if ((Test-Path -LiteralPath $destination) -and (Test-PointsToSource -Destination $destination -Source $source)) {
            Write-Action 'OK' $relative
            continue
        }

        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if ($item.PSIsContainer -and -not $item.LinkType) {
                Write-Warning "CONFLITO $relative (e um diretorio; nao sera movido automaticamente)"
                $failures++
                continue
            }
            if (-not $Backup) {
                Write-Warning "CONFLITO $relative (use -Backup para preservar o original)"
                $failures++
                continue
            }

            $backupPath = Join-Path $BackupRoot $relative
            Write-Action 'BACKUP' "$relative -> $backupPath"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
                Move-Item -LiteralPath $destination -Destination $backupPath -Force
            }
        }

        Write-Action (Get-Tag 'LINK?' 'LINK') "$relative -> $source"
        if ($DryRun) { continue }

        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        try {
            New-Item -ItemType SymbolicLink -Path $destination -Target $source -Force | Out-Null
        } catch {
            Write-Warning "Falha ao criar symlink $destination (ative o Modo de desenvolvedor ou rode como administrador): $_"
            $failures++
        }
    }

    if ($failures -gt 0) {
        throw "$failures conflito(s) encontrado(s); nada conflitante foi sobrescrito"
    }
}

function Restore-Backups {
    if (-not (Test-Path -LiteralPath $BackupBase)) {
        throw "Diretorio de backups ausente: $BackupBase"
    }
    $snapshot = Get-ChildItem -LiteralPath $BackupBase -Directory |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
        Sort-Object Name | Select-Object -Last 1
    if (-not $snapshot) {
        throw "Nenhum backup encontrado em $BackupBase"
    }

    Write-Action 'BACKUP' $snapshot.Name
    Get-ChildItem -LiteralPath $snapshot.FullName -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($snapshot.FullName.Length + 1)
        $destination = Join-Path $Target $relative
        Write-Action (Get-Tag 'RESTORE?' 'RESTORE') "$relative <- $($_.FullName)"
        if ($DryRun) { return }
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-Output $(if ($DryRun) { 'Dry-run de restauracao concluido.' } else { "Backup restaurado; copia preservada em $($snapshot.FullName)" })
}

function Get-WindowsTerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Set-WindowsTerminalTheme {
    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        Write-Warning 'Windows Terminal settings.json nao encontrado; pulei o tema do terminal.'
        return
    }

    $schemeSource = Join-Path $SourceRoot 'windows-terminal\sword-art-online.scheme.json'
    $scheme = Get-Content -LiteralPath $schemeSource -Raw | ConvertFrom-Json

    $rawLines = Get-Content -LiteralPath $settingsPath
    $cleanJson = ($rawLines | Where-Object { $_.Trim() -notmatch '^//' }) -join "`n"
    $settings = $cleanJson | ConvertFrom-Json

    if (-not $settings.schemes) {
        $settings | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force
    }
    $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne 'Sword Art Online' })
    $settings.schemes += $scheme

    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $settings.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue 'Sword Art Online' -Force
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $settings.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue 'JetBrainsMono NF' -Force

    Write-Action (Get-Tag 'THEME?' 'THEME') "Windows Terminal -> Sword Art Online ($settingsPath)"
    if ($DryRun) { return }

    $backupPath = Join-Path $BackupRoot 'windows-terminal\settings.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding utf8
}

function Set-Wallpaper {
    $wallpaperDir = Join-Path $Target 'Pictures\Wallpapers\sword-art-omarchy'
    $files = @('1-ember.png', '2-horizon.png', '3-void.png')
    $baseUrl = 'https://raw.githubusercontent.com/KitsuneSemCalda/Sword-Art-Omarchy/master/backgrounds'

    Write-Action (Get-Tag 'WALL?' 'WALL') "Papeis de parede -> $wallpaperDir"
    if ($DryRun) { return }

    New-Item -ItemType Directory -Force -Path $wallpaperDir | Out-Null
    foreach ($file in $files) {
        $destination = Join-Path $wallpaperDir $file
        if (-not (Test-Path -LiteralPath $destination)) {
            Invoke-WebRequest -Uri "$baseUrl/$file" -OutFile $destination
        }
    }

    $chosen = Join-Path $wallpaperDir '2-horizon.png'
    Add-Type -Namespace SAO -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
    [SAO.Wallpaper]::SystemParametersInfo(20, 0, $chosen, 3) | Out-Null
}

function Get-RainmeterExe {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Rainmeter\Rainmeter.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

# AincradHUD (home/rainmeter/AincradHUD) e' symlinkado para
# Documents\Rainmeter\Skins\AincradHUD pelo Install-Symlinks normal (ver
# Get-LinkMap). Esta funcao so ativa esse skin e desativa o pacote de
# terceiros SAO-Skin-Pack/RedDragon caso tenha sido instalado manualmente
# antes (duplicava CPU/RAM/relogio e dependia de um feed RSS externo).
# Rainmeter.ini e' UTF-16 com BOM (Set-Content -Encoding Unicode preserva).
function Set-RainmeterHud {
    $rainmeterIni = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
    if (-not (Test-Path -LiteralPath $rainmeterIni)) {
        Write-Warning 'Rainmeter.ini nao encontrado; abra o Rainmeter uma vez antes de rodar -Theme.'
        return
    }

    Write-Action (Get-Tag 'HUD?' 'HUD') "AincradHUD -> Active=1 em $rainmeterIni"
    if ($DryRun) { return }

    $backupPath = Join-Path $BackupRoot 'rainmeter\Rainmeter.ini'
    New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
    Copy-Item -LiteralPath $rainmeterIni -Destination $backupPath -Force

    $lines = Get-Content -LiteralPath $rainmeterIni -Encoding Unicode
    $currentSection = ''
    $sawAincradSection = $false
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $currentSection = $matches[1] }
        if ($currentSection -eq 'AincradHUD') {
            $sawAincradSection = $true
            if ($line -match '^\s*AlwaysOnTop\s*=\s*$') { 'AlwaysOnTop=1'; continue }
        }
        if ($currentSection -like 'Sword Art Online\*' -and $line -match '^\s*Active\s*=\s*1\s*$') {
            'Active=0'
            continue
        }
        $line
    }
    if (-not $sawAincradSection) {
        $out += @('', '[AincradHUD]', 'Active=1', 'AlwaysOnTop=1')
    }
    Set-Content -LiteralPath $rainmeterIni -Value $out -Encoding Unicode

    $rainmeterExe = Get-RainmeterExe
    if (-not $rainmeterExe) {
        Write-Warning 'Rainmeter nao encontrado; a config foi ajustada, mas o app nao foi (re)iniciado.'
        return
    }
    Get-Process -Name Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    Start-Process -FilePath $rainmeterExe
}

function Install-LexendFont {
    $fontDir = Join-Path $Target '.local\share\fonts\lexend'
    $weights = @{ 'Lexend-Regular.ttf' = 400; 'Lexend-Bold.ttf' = 700 }

    if (-not ($weights.Keys | Where-Object { -not (Test-Path (Join-Path $fontDir $_)) })) {
        Write-Action 'OK' 'arquivos da fonte Lexend ja baixados'
    } else {
        Write-Action (Get-Tag 'FONT?' 'FONT') "Lexend -> $fontDir"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
            $css = Invoke-WebRequest -Uri 'https://fonts.googleapis.com/css2?family=Lexend:wght@400;700' -UserAgent 'Mozilla/5.0' -UseBasicParsing | Select-Object -ExpandProperty Content
            $urlByWeight = @{}
            [regex]::Matches($css, "font-weight:\s*(\d+);\s*[\s\S]*?src:\s*url\(([^)]+)\)") | ForEach-Object {
                $urlByWeight[[int]$_.Groups[1].Value] = $_.Groups[2].Value
            }
            foreach ($file in $weights.Keys) {
                $weight = $weights[$file]
                if ($urlByWeight.ContainsKey($weight)) {
                    Invoke-WebRequest -Uri $urlByWeight[$weight] -OutFile (Join-Path $fontDir $file)
                }
            }
        }
    }

    Register-UserFonts -Directory $fontDir
}

function Install-NerdFont {
    $fontDir = Join-Path $Target '.local\share\fonts\jetbrainsmono-nf'
    if (Test-Path -LiteralPath (Join-Path $fontDir 'JetBrainsMonoNerdFontMono-Regular.ttf')) {
        Write-Action 'OK' 'JetBrainsMono Nerd Font ja baixada'
        Register-UserFonts -Directory $fontDir
        return
    }

    Write-Action (Get-Tag 'FONT?' 'FONT') "JetBrainsMono Nerd Font -> $fontDir"
    if ($DryRun) { return }

    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    $zipPath = Join-Path $env:TEMP 'JetBrainsMono-NerdFont.zip'
    Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $fontDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    Register-UserFonts -Directory $fontDir
}

function Register-UserFonts {
    param([string]$Directory)
    if ($DryRun) { return }

    $userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $userFontDir | Out-Null
    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

    Get-ChildItem -LiteralPath $Directory -Filter '*.ttf' -Recurse | ForEach-Object {
        $target = Join-Path $userFontDir $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        $displayName = "$([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) (TrueType)"
        New-ItemProperty -Path $regPath -Name $displayName -Value $_.Name -PropertyType String -Force | Out-Null
    }
}

function Install-Apps {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning 'winget nao encontrado; instale as ferramentas manualmente (ver README.md).'
        return
    }

    # Ferramentas do tema (janela/terminal/prompt/HUD).
    $themePackages = @(
        'glzr-io.glazewm',
        'Microsoft.WindowsTerminal',
        'Microsoft.PowerToys',
        'Starship.Starship',
        'Rainmeter.Rainmeter',
        'junegunn.fzf'
    )

    # Perfil pessoal de apps, equivalente ao ensure_apps() do omarchy.pl.
    $profilePackages = @(
        'Valve.Steam',
        'PrismLauncher.PrismLauncher',
        'Git.Git',
        'Anthropic.Claude',
        'OpenAI.Codex',
        'Bitwarden.Bitwarden',
        'Obsidian.Obsidian',
        'AppFlowy.AppFlowy',
        'Microsoft.VisualStudioCode',
        'GoLang.Go',
        'OpenJS.NodeJS',
        'Python.Python.3.13',
        'DEVCOM.Lua'
    )

    foreach ($package in ($themePackages + $profilePackages)) {
        Write-Action (Get-Tag 'RUN?' 'RUN') "winget install --id $package"
        if (-not $DryRun) {
            winget install --id $package --source winget --accept-source-agreements --accept-package-agreements --silent
        }
    }
}

# Modulos PowerShell Gallery usados pelo profile (Terminal-Icons, PSFzf, z):
# carregados sob demanda via PowerShell.OnIdle no profile, mas precisam estar
# instalados de antemao. -CurrentUser porque -Fonts/-Theme tambem so tocam o
# HOME real, sem exigir admin.
function Install-PowerShellModules {
    $modules = @('Terminal-Icons', 'PSFzf', 'z')
    foreach ($name in $modules) {
        if (Get-Module -ListAvailable -Name $name) {
            Write-Action 'OK' "modulo $name ja instalado"
            continue
        }
        Write-Action (Get-Tag 'RUN?' 'RUN') "Install-Module $name -Scope CurrentUser"
        if (-not $DryRun) {
            Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber
        }
    }
}

if ($Restore) {
    Restore-Backups
    exit 0
}

Install-Symlinks
if ($Fonts) {
    Install-LexendFont
    Install-NerdFont
}
if ($Theme) {
    Set-WindowsTerminalTheme
    Set-Wallpaper
    Set-RainmeterHud
}
if ($Apps) {
    Install-Apps
    Install-PowerShellModules
}

Write-Output $(if ($DryRun) { 'Dry-run concluido.' } else { 'Dotfiles instalados.' })
