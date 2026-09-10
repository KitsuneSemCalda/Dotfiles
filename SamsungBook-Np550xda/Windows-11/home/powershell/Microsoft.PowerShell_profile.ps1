# Perfil do PowerShell - Windows-11 dotfiles (tema Sword Art Online)
# Sem acentos de proposito: PowerShell 5.1 le perfis sem BOM como ANSI, o que
# corrompe literais acentuados neste ambiente.
#
# Instalado via win11.ps1 em $PROFILE (normalmente
# Documents\PowerShell\Microsoft.PowerShell_profile.ps1 no PowerShell 7, ou
# Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1 no 5.1).

# [char]27 em vez do escape `e: `e so existe a partir do PowerShell 6+, e
# esse profile precisa rodar tambem no Windows PowerShell 5.1 (onde um
# escape desconhecido vira so a letra solta - "e[38;2;..." em vez da cor).
$esc = [char]27
$cyan  = "$esc[38;2;62;232;255m"   # accent cyan (#3ee8ff)
$blue  = "$esc[38;2;79;141;255m"   # blue (#4f8dff)
$green = "$esc[38;2;77;255;166m"   # green (#4dffa6)
$red   = "$esc[38;2;255;59;92m"    # red / "HP" (#ff3b5c)
$reset = "$esc[0m"

# Mesmo starship.toml usado no perfil Omarchy (~/.config/starship.toml e
# %USERPROFILE%\.config\starship.toml resolvem para o mesmo lugar logico).
# Starship e' um binario nativo (Rust): o prompt com git branch/status sai
# dele em vez de um "prompt" PowerShell feito a mao chamando git.exe.
#
# `starship init powershell` sempre gera o mesmo script para a mesma versao
# + config, mas spawnar o processo starship.exe a cada abertura de shell
# custa ~500ms so no exec (medido: primeiro spawn no processo pwsh recem
# aberto). Cacheamos a saida em disco e so regeneramos quando o binario ou
# o starship.toml mudarem (por data de modificacao).
$starshipCmd = Get-Command starship -ErrorAction SilentlyContinue
if ($starshipCmd) {
    $env:STARSHIP_CONFIG = Join-Path $env:USERPROFILE '.config\starship.toml'

    $cacheDir  = Join-Path $env:LOCALAPPDATA 'powershell-starship-cache'
    $cacheFile = Join-Path $cacheDir 'init.ps1'

    $needsRegen = $true
    if (Test-Path $cacheFile) {
        $cacheTime = (Get-Item $cacheFile).LastWriteTimeUtc
        $srcTimes  = @((Get-Item $starshipCmd.Source).LastWriteTimeUtc)
        if (Test-Path $env:STARSHIP_CONFIG) {
            $srcTimes += (Get-Item $env:STARSHIP_CONFIG).LastWriteTimeUtc
        }
        $needsRegen = ($srcTimes | Measure-Object -Maximum).Maximum -gt $cacheTime
    }

    if ($needsRegen) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        &starship init powershell | Out-File -FilePath $cacheFile -Encoding utf8 -Force
    }

    . $cacheFile
}

if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -Colors @{
        Command   = $cyan
        Parameter = $blue
        String    = $green
        Error     = $red
    }
    # PredictionSource pode lancar (nao so falhar silenciosamente) em consoles
    # sem suporte a VT (saida redirecionada, alguns hosts nao interativos).
    try { Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView } catch {}
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
}

Write-Host "$cyan[ LINK START ]$reset"

Set-Alias ll Get-ChildItem
Set-Alias lint Invoke-ScriptAnalyzer

# --- Ergonomics modules ---
# Import-Module e' sincrono e cada um destes custa dezenas a centenas de ms.
# Defer todos pro primeiro idle logo apos o prompt renderizar, pra shell ficar
# interativa na hora e os modulos anexarem silenciosamente uma fracao de
# segundo depois.
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    Import-Module z -ErrorAction SilentlyContinue
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Import-Module CompletionPredictor -ErrorAction SilentlyContinue
    Import-Module F7History -ErrorAction SilentlyContinue

    if (Get-Module PSFzf) {
        try {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        } catch {}
    }

    # CompletionPredictor precisa estar importado antes de virar fonte de
    # predicao; troca de History pra HistoryAndPlugin so' depois do import.
    if (Get-Module CompletionPredictor) {
        try { Set-PSReadLineOption -PredictionSource HistoryAndPlugin } catch {}
    }
} | Out-Null
