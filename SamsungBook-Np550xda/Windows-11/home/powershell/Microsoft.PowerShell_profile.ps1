# Perfil do PowerShell - Windows-11 dotfiles (tema Sword Art Online)
# Sem acentos de proposito: PowerShell 5.1 le perfis sem BOM como ANSI, o que
# corrompe literais acentuados neste ambiente.
#
# Instalado via dotfiles.ps1 em $PROFILE (normalmente
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
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $env:STARSHIP_CONFIG = Join-Path $env:USERPROFILE '.config\starship.toml'
    Invoke-Expression (&starship init powershell)
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

# --- Ergonomics modules ---
# Terminal-Icons/z/PSFzf together add roughly 1s of synchronous Import-Module
# time to every shell startup. Defer them to the first idle moment right
# after the prompt renders, so the terminal is interactive immediately and
# these attach silently a fraction of a second later.
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    Import-Module z -ErrorAction SilentlyContinue
    Import-Module PSFzf -ErrorAction SilentlyContinue

    if (Get-Module PSFzf) {
        try {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        } catch {}
    }
} | Out-Null
