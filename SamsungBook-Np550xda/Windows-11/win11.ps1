#!/usr/bin/env pwsh
<#
win11.ps1 - instalador/orquestrador dos dotfiles Windows-11.
Equivalente em espirito ao omarchy.pl do perfil Omarchy: por padrao nao
altera nada quando ha conflito, cria symlinks para os arquivos de
configuracao simples e usa flags separadas para as acoes que mexem em
sistema (fontes, tema, apps).

Sem acentos de proposito nas strings/comentarios: Windows PowerShell 5.1 le
.ps1 sem BOM como ANSI, o que corrompe literais acentuados neste ambiente.

Uso:
  pwsh ./win11.ps1 -DryRun              # mostra o que seria feito
  pwsh ./win11.ps1 -Backup              # symlinks, preservando conflitos
  pwsh ./win11.ps1 -Restore             # restaura o backup mais recente
  pwsh ./win11.ps1 -Fonts               # instala Lexend + JetBrainsMono Nerd Font
  pwsh ./win11.ps1 -Theme               # aplica color scheme + wallpaper SAO
  pwsh ./win11.ps1 -Apps                # winget install das ferramentas usadas
  pwsh ./win11.ps1 -All -Backup         # tudo de uma vez

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

# Cada entrada registra onde um item de backup precisa voltar (Destination) e
# o hash do conteudo pos-instalacao (Hash), usado pelo restore para detectar
# se algo mudou o destino depois da instalacao antes de sobrescrever.
$script:BackupManifest = @()

function Add-BackupManifestEntry {
    param([string]$RelativePath, [string]$Destination, [string]$Hash)
    $script:BackupManifest += [pscustomobject]@{
        RelativePath = $RelativePath
        Destination  = $Destination
        Hash         = $Hash
    }
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

# Formata a lista de mudancas ja aplicadas para uma mensagem de erro, usada
# quando a passagem de aplicacao falha depois que a validacao ja passou.
function Get-AppliedSummary {
    param([string[]]$Applied)
    if ($Applied.Count -eq 0) { return 'Nenhuma mudanca foi aplicada antes da falha.' }
    return "Mudancas ja aplicadas antes da falha: $($Applied -join ', ')."
}

function Install-Symlinks {
    # Passagem de validacao (somente leitura): monta o plano de acao para
    # cada item antes de tocar em qualquer coisa. Se houver conflito, aborta
    # aqui sem ter criado nenhum link ou movido nenhum backup.
    $plan = @()
    $conflicts = @()

    foreach ($entry in Get-LinkMap) {
        $source = Join-Path $SourceRoot $entry.Source
        $destination = $entry.Destination
        $relative = $entry.Source

        if (-not (Test-Path -LiteralPath $source)) {
            $conflicts += "$relative (origem ausente: $source)"
            continue
        }

        if ((Test-Path -LiteralPath $destination) -and (Test-PointsToSource -Destination $destination -Source $source)) {
            $plan += [pscustomobject]@{ Relative = $relative; Action = 'Ok' }
            continue
        }

        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if ($item.PSIsContainer -and -not $item.LinkType) {
                $conflicts += "$relative (e um diretorio; nao sera movido automaticamente)"
                continue
            }
            if (-not $Backup) {
                $conflicts += "$relative (use -Backup para preservar o original)"
                continue
            }

            $plan += [pscustomobject]@{ Relative = $relative; Source = $source; Destination = $destination; Action = 'BackupLink' }
            continue
        }

        $plan += [pscustomobject]@{ Relative = $relative; Source = $source; Destination = $destination; Action = 'Link' }
    }

    if ($conflicts.Count -gt 0) {
        foreach ($conflict in $conflicts) { Write-Warning "CONFLITO $conflict" }
        throw "$($conflicts.Count) conflito(s) encontrado(s); validacao falhou e nada foi alterado"
    }

    # Passagem de aplicacao: so comeca depois que a validacao inteira passou.
    $applied = @()
    foreach ($item in $plan) {
        if ($item.Action -eq 'Ok') {
            Write-Action 'OK' $item.Relative
            continue
        }

        if ($item.Action -eq 'BackupLink') {
            $backupPath = Join-Path $BackupRoot $item.Relative
            Write-Action 'BACKUP' "$($item.Relative) -> $backupPath"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
                try {
                    Move-Item -LiteralPath $item.Destination -Destination $backupPath -Force
                } catch {
                    throw "Falha ao mover $($item.Destination) para $backupPath : $_`n$(Get-AppliedSummary $applied)"
                }
                $applied += "BACKUP $($item.Relative)"
                $sourceHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
                Add-BackupManifestEntry -RelativePath $item.Relative -Destination $item.Destination -Hash $sourceHash
            }
        }

        Write-Action (Get-Tag 'LINK?' 'LINK') "$($item.Relative) -> $($item.Source)"
        if ($DryRun) { continue }

        New-Item -ItemType Directory -Force -Path (Split-Path $item.Destination) | Out-Null
        try {
            New-Item -ItemType SymbolicLink -Path $item.Destination -Target $item.Source -Force | Out-Null
        } catch {
            throw "Falha ao criar symlink $($item.Destination) (ative o Modo de desenvolvedor ou rode como administrador): $_`n$(Get-AppliedSummary $applied)"
        }
        $applied += "LINK $($item.Relative)"
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

    $manifestPath = Join-Path $snapshot.FullName 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Manifesto de restauracao ausente em $manifestPath (backup incompativel ou corrompido)"
    }
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    Write-Action 'BACKUP' $snapshot.Name

    # Primeira passagem: so valida. Se algo mudou o destino depois da
    # instalacao (conflito), aborta sem tocar em nenhum arquivo.
    $conflicts = @()
    foreach ($entry in $manifest) {
        $destination = $entry.Destination
        if (Test-Path -LiteralPath $destination) {
            $currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            if ($currentHash -and $currentHash -ne $entry.Hash) {
                $conflicts += "$destination (conteudo mudou desde a instalacao)"
            }
        }
    }
    if ($conflicts.Count -gt 0) {
        throw "Conflito(s) detectado(s); nada foi restaurado:`n" + ($conflicts -join "`n")
    }

    foreach ($entry in $manifest) {
        $backupFile = Join-Path $snapshot.FullName $entry.RelativePath
        $destination = $entry.Destination
        Write-Action (Get-Tag 'RESTORE?' 'RESTORE') "$destination <- $backupFile"
        if ($DryRun) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        Copy-Item -LiteralPath $backupFile -Destination $destination -Force
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

    $backupRelative = 'windows-terminal\settings.json'
    $backupPath = Join-Path $BackupRoot $backupRelative
    New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding utf8
    $hash = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
    Add-BackupManifestEntry -RelativePath $backupRelative -Destination $settingsPath -Hash $hash
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

    $backupRelative = 'rainmeter\Rainmeter.ini'
    $backupPath = Join-Path $BackupRoot $backupRelative
    New-Item -ItemType Directory -Force -Path (Split-Path $backupPath) | Out-Null
    Copy-Item -LiteralPath $rainmeterIni -Destination $backupPath -Force

    $lines = Get-Content -LiteralPath $rainmeterIni -Encoding Unicode
    $currentSection = ''
    $inAincrad = $false
    $sawAincradSection = $false
    $sawActive = $false
    $sawAlwaysOnTop = $false
    $out = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            if ($inAincrad) {
                if (-not $sawActive) { $out.Add('Active=1') }
                if (-not $sawAlwaysOnTop) { $out.Add('AlwaysOnTop=1') }
            }
            $currentSection = $matches[1]
            $inAincrad = ($currentSection -eq 'AincradHUD')
            if ($inAincrad) {
                $sawAincradSection = $true
                $sawActive = $false
                $sawAlwaysOnTop = $false
            }
            $out.Add($line)
            continue
        }

        if ($inAincrad -and $line -match '^\s*Active\s*=') {
            $out.Add('Active=1')
            $sawActive = $true
            continue
        }
        if ($inAincrad -and $line -match '^\s*AlwaysOnTop\s*=') {
            $out.Add('AlwaysOnTop=1')
            $sawAlwaysOnTop = $true
            continue
        }

        if ($currentSection -like 'Sword Art Online\*' -and $line -match '^\s*Active\s*=\s*1\s*$') {
            $out.Add('Active=0')
            continue
        }
        $out.Add($line)
    }
    if ($inAincrad) {
        if (-not $sawActive) { $out.Add('Active=1') }
        if (-not $sawAlwaysOnTop) { $out.Add('AlwaysOnTop=1') }
    }
    if (-not $sawAincradSection) {
        $out.Add('')
        $out.Add('[AincradHUD]')
        $out.Add('Active=1')
        $out.Add('AlwaysOnTop=1')
    }
    Set-Content -LiteralPath $rainmeterIni -Value $out -Encoding Unicode
    $hash = (Get-FileHash -LiteralPath $rainmeterIni -Algorithm SHA256).Hash
    Add-BackupManifestEntry -RelativePath $backupRelative -Destination $rainmeterIni -Hash $hash

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
    $nerdFontsVersion = 'v3.5.1'
    Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/download/$nerdFontsVersion/JetBrainsMono.zip" -OutFile $zipPath
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

    $failures = 0
    foreach ($package in ($themePackages + $profilePackages)) {
        winget list --id $package --exact --accept-source-agreements *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Action 'OK' "$package ja instalado"
            continue
        }

        Write-Action (Get-Tag 'RUN?' 'RUN') "winget install --id $package"
        if ($DryRun) { continue }

        winget install --id $package --source winget --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Falha ao instalar $package (winget saiu com codigo $LASTEXITCODE)"
            $failures++
        }
    }

    if ($failures -gt 0) {
        throw "$failures pacote(s) falharam ao instalar via winget"
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
if ($Apps) {
    Install-Apps
    Install-PowerShellModules
}
if ($Theme) {
    Set-WindowsTerminalTheme
    Set-Wallpaper
    Set-RainmeterHud
}

if ($script:BackupManifest.Count -gt 0) {
    $manifestPath = Join-Path $BackupRoot 'manifest.json'
    $script:BackupManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

Write-Output $(if ($DryRun) { 'Dry-run concluido.' } else { 'Dotfiles instalados.' })
