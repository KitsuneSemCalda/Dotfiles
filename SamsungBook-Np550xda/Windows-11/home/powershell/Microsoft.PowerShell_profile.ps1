# Perfil do PowerShell - Windows-11 dotfiles (tema Sword Art Online)
# Sem acentos de proposito: PowerShell 5.1 le perfis sem BOM como ANSI, o que
# corrompe literais acentuados neste ambiente.
#
# Instalado via dotfiles.ps1 em $PROFILE (normalmente
# Documents\PowerShell\Microsoft.PowerShell_profile.ps1 no PowerShell 7, ou
# Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1 no 5.1).

# Mesmo starship.toml usado no perfil Omarchy (~/.config/starship.toml e
# %USERPROFILE%\.config\starship.toml resolvem para o mesmo lugar logico).
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $env:STARSHIP_CONFIG = Join-Path $env:USERPROFILE '.config\starship.toml'
    Invoke-Expression (&starship init powershell)
}

if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -Colors @{
        Command   = "`e[38;2;62;232;255m"   # accent cyan (#3ee8ff)
        Parameter = "`e[38;2;79;141;255m"   # blue (#4f8dff)
        String    = "`e[38;2;77;255;166m"   # green (#4dffa6)
        Error     = "`e[38;2;255;59;92m"    # red / "HP" (#ff3b5c)
    }
    Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
}

$linkStartColor = "`e[38;2;62;232;255m"
$resetColor = "`e[0m"
Write-Host "$linkStartColor>> Link Start.$resetColor"

Set-Alias ll Get-ChildItem
