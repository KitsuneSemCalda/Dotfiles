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
# O custo pesado de verdade (~300-400ms, medido) NAO e' o spawn do
# starship.exe (isso sozinho custa so' ~25-50ms) - e' o `New-Module` com
# dezenas de funcoes que `starship init powershell` gera, que o PowerShell
# tem que parsear/compilar do zero a cada processo novo (nao existe cache
# de bytecode entre processos, cachear o texto do script no disco nao
# ataca essa parte). Por isso isso e' adiado pro mesmo gatilho de `prompt`
# usado pros modulos mais abaixo, em vez de rodar aqui e atrasar a
# abertura do shell.
#
# `--print-full-init` evita que a cache em disco guarde so' o wrapper
# preguicoso de 1 linha que `starship init powershell` (sem essa flag)
# gera - esse wrapper respawna o starship.exe de novo em todo dot-source
# do cache, entao a cache antiga nunca pegava a parte cara mesmo. Ainda
# assim cacheamos em disco pra so' regenerar quando o binario ou o
# starship.toml mudarem (por data de modificacao).
function global:__Initialize-StarshipPrompt {
    $starshipCmd = Get-Command starship -ErrorAction SilentlyContinue
    if (-not $starshipCmd) { return }

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
        &starship init powershell --print-full-init | Out-File -FilePath $cacheFile -Encoding utf8 -Force
    }

    # O script cacheado define `function global:prompt` sozinho e
    # substitui o wrapper deferido de baixo assim que roda - so' precisa
    # disso uma vez por sessao, os proximos renders ja' chamam o prompt
    # do starship direto, sem passar por esse arquivo de novo.
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

# --- Ergonomics modules + prompt do starship ---
# Import-Module e' sincrono e cada um destes custa dezenas a centenas de ms;
# o init do starship custa mais uns ~300-400ms sozinho (ver comentario la'
# em cima). Tudo isso e' adiado pro mesmo gatilho.
#
# Terminal-Icons/z/PSFzf tem que estar instalados em
# Documents\PowerShell\Modules (o PSModulePath do pwsh 7), NAO so' em
# Documents\WindowsPowerShell\Modules (Windows PowerShell 5.1). Os dois
# ficam lado a lado no disco, mas o pwsh 7 real (nao "-NoProfile") so'
# enxerga o primeiro - foi por isso que esses 3 modulos nunca carregavam
# aqui mesmo com o Import-Module "funcionando" em testes -NoProfile.
#
# Tentativa original: `Register-EngineEvent -SourceIdentifier PowerShell.OnIdle`.
# Nao funciona: esse evento so' dispara via o processamento de idle classico
# do ConsoleHost, e o PSReadLine assume o loop de leitura do prompt sem
# repassar pra ele - confirmado na pratica (Get-Module Terminal-Icons ficava
# vazio pra sempre numa sessao interativa real, mesmo parado no prompt).
#
# Em vez disso, penduramos tudo na propria funcao `prompt`: todo host
# chama `prompt` de verdade, entao e' um gatilho confiavel. A 1a renderizacao
# sai instantanea (prompt padrao do PowerShell, sem starship nem modulos); o
# carregamento pesado roda uma unica vez logo antes da 2a renderizacao (ou
# seja, o usuario sente a pausa depois do primeiro Enter, nao na abertura
# do shell - e o prompt do starship "aparece" a partir dai').
$global:__DeferredModulesPending = $true
$global:__PromptCallCount = 0
$global:__OriginalPrompt = $function:prompt

function global:prompt {
    $global:__PromptCallCount++
    if ($global:__DeferredModulesPending -and $global:__PromptCallCount -gt 1) {
        $global:__DeferredModulesPending = $false

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

        # Por ultimo: isso substitui `global:prompt` (ver comentario na
        # funcao). A partir do proximo render, este wrapper nem roda mais.
        __Initialize-StarshipPrompt
    }

    & $global:__OriginalPrompt
}
