# Dotfiles para Windows 11 — Samsung Book NP550XDA

Base inicial de dotfiles para o mesmo Samsung NP550XDA-KF2BR do
[perfil Omarchy](../Omarchy/README.md), agora no boot com Windows 11. Tema
visual inspirado em Sword Art Online, reaproveitando a paleta e o material
do tema [Sword Art Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy)
já criado para o Hyprland — assim os dois sistemas operacionais mantêm a
mesma identidade visual. O snapshot de hardware usado para as decisões está
em [`hardware/hardware-profile.txt`](hardware/hardware-profile.txt).

## Regras seguidas

1. **Tema principal: Sword Art Online.** Paleta idêntica ao tema Omarchy
   (fundo `#08090a`, painel `#16181b`, accent ciano `#3ee8ff`, HP vermelho
   `#ff3b5c`, MP azul `#4f8dff`) aplicada de ponta a ponta — nada gerado por
   IA neste repositório, tudo reaproveitado do que já existe:
   - Wallpapers e paleta: [Sword-Art-Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy)
     (os mesmos 3 papéis de parede 4K de textura de carbono do tema
     original — `dotfiles.ps1 -Theme` baixa e aplica automaticamente).
   - Widgets de desktop no estilo SAO (RAM/CPU/relógio/RSS): o Rainmeter
     [SAO-Skin-Pack](https://github.com/rensatsu/SAO-Skin-Pack) é a opção
     mais próxima do plugin Feader-RSS do Omarchy. `dotfiles.ps1 -Theme`
     baixa o pacote na hora da instalação e **recolore** as barras de HP/MP
     para a paleta exata acima (troca de matiz/saturação preservando luz e
     sombra de cada pixel — recolor mecânico, não geração de imagem) antes
     de instalar em `Documents\Rainmeter\Skins`. Ver "Widgets de desktop
     (Rainmeter)" abaixo para o detalhe de como isso funciona.
2. **Manter os keybinds do Omarchy onde possível.** O Windows não tem um
   compositor tiling nativo, então o `GlazeWM` (https://github.com/glzr-io/glazewm,
   FOSS, Rust, o tiling WM para Windows mais parecido com Hyprland/i3) recebe
   uma configuração com os atalhos do
   [manual de hotkeys do Omarchy](https://omarchy.org/manual/hotkeys/)
   remapeados para `SUPER`, com bordas na mesma paleta (foco = accent ciano,
   inativa = cinza `#4a5058` do tema). Onde não há equivalente no Windows
   (`Ctrl+Alt+Del` é reservado pelo SO, por exemplo), fica documentado em vez
   de forçado — ver a tabela completa mais abaixo.

GlazeWM e o Rainmeter são as duas peças visuais do setup (janelas e HUD de
desktop, respectivamente) e devem continuar sendo as ferramentas usadas para
isso — qualquer evolução futura do tema deve mexer na paleta compartilhada
(`#08090a`/`#16181b`/`#3ee8ff`/`#ff3b5c`/`#4f8dff`) em vez de trocar de
ferramenta.

## Perfil da máquina

- Intel Core i5-1135G7, 4 núcleos / 8 threads
- 16 GiB de RAM
- Intel Iris Xe
- Tela interna 1920×1080
- NVMe Samsung de aproximadamente 256 GiB
- Windows 11 Home Single Language

## Estrutura

```text
home/
├── glazewm/config.yaml                  # tiling WM + keybinds do Omarchy
├── starship.toml                        # idêntico ao usado no Omarchy
├── powershell/Microsoft.PowerShell_profile.ps1
└── windows-terminal/
    └── sword-art-online.scheme.json     # paleta do Sword Art Omarchy
hardware/
└── hardware-profile.txt
dotfiles.ps1                             # instalador e orquestrador
scripts/hardware-profile.ps1             # atualiza o snapshot (sem PII)
scripts/debloat.ps1                      # debloat + otimizacao conservadores
```

Assim como no Omarchy, os arquivos de configuração ficam nos formatos
nativos de cada ferramenta (YAML no GlazeWM, JSON no Windows Terminal, TOML
no Starship) e o PowerShell cuida só da automação/instalação.

## Ferramentas usadas

Todas de projetos existentes e mantidos — nenhuma escrita do zero:

| Papel no Omarchy       | Ferramenta no Windows                                          |
|-------------------------|-----------------------------------------------------------------|
| Hyprland (tiling WM)    | [GlazeWM](https://github.com/glzr-io/glazewm)                   |
| Alacritty (terminal)    | Windows Terminal                                                 |
| Starship (prompt)       | Starship (mesmo `starship.toml`)                                 |
| btop                    | [btop4win](https://github.com/aristocratos/btop4win)             |
| Menu/launcher do Omarchy| PowerToys Run                                                    |
| Feader-RSS / widgets    | SAO-Skin-Pack (Rainmeter, recolorido automaticamente — ver abaixo) |

## Perfil de apps

Equivalente ao `ensure_apps()` do `omarchy.pl`: `-Apps`/`-All` também instala,
via `winget`, o perfil pessoal de aplicativos além das ferramentas do tema.

| App           | Pacote winget                   |
|---------------|----------------------------------|
| Steam         | `Valve.Steam`                    |
| Prism Launcher| `PrismLauncher.PrismLauncher`    |
| Git           | `Git.Git`                        |
| Claude        | `Anthropic.Claude`               |
| Codex CLI     | `OpenAI.Codex`                   |
| Bitwarden     | `Bitwarden.Bitwarden`            |
| Obsidian      | `Obsidian.Obsidian`              |
| AppFlowy      | `AppFlowy.AppFlowy`              |
| VS Code       | `Microsoft.VisualStudioCode`     |
| Go            | `GoLang.Go`                      |
| Node.js       | `OpenJS.NodeJS`                  |
| Python        | `Python.Python.3.13`             |
| Lua           | `DEVCOM.Lua`                     |

## Debloat e otimização

`scripts/debloat.ps1` é conservador de propósito e construído a partir do
`Get-AppxPackage` **real** desta máquina (não uma lista genérica baixada da
internet) — por isso não mexe em Defender, Windows Update, OneDrive, Edge,
WSL, Dev Home, nada da Samsung (pode controlar hardware de verdade) nem em
apps claramente instalados de propósito (Claude, ChatGPT Desktop, Dropbox,
Spotify). O que ele faz:

- Remove bloatware sem uso pra este perfil: Clipchamp, Bing News/Weather,
  Get Help, Solitaire Collection, Feedback Hub, novo Outlook, Teams
  (consumidor), Copilot e Family Safety.
- Desativa (não apaga — reversível com `Enable-ScheduledTask`) tarefas
  agendadas de telemetria/diagnóstico conhecidas (Compatibility Appraiser,
  CEIP, Disk Diagnostic, Feedback, Error Reporting).
- Ativa o Storage Sense (limpeza automática de temporários do Windows).
- Limpa `%TEMP%`, `C:\Windows\Temp` e a Lixeira.

Desativar as tarefas do sistema exige administrador; se rodado sem
elevação, o próprio script se relança elevado (`-Verb RunAs`) e pede
confirmação por UAC.

```powershell
pwsh ./scripts/debloat.ps1              # so mostra o que seria feito
pwsh ./scripts/debloat.ps1 -Apply       # aplica de verdade (pede UAC)
```

## Keybinds: Omarchy → Windows (GlazeWM)

| Atalho Omarchy         | Ação                        | No Windows                              |
|-------------------------|-----------------------------|------------------------------------------|
| `Super+Return`          | Terminal                    | `Super+Return` → Windows Terminal        |
| `Super+W` / `Super+Q`   | Fechar janela                | igual                                     |
| `Super+T`               | Alternar tiling/floating     | igual                                     |
| `Super+F`               | Tela cheia                  | igual                                     |
| `Super+Seta`            | Mover foco                  | igual (+ `Super+HJKL` como bônus)         |
| `Super+Shift+Seta`      | Trocar janelas de posição    | igual                                     |
| `Super+1..4`            | Ir para workspace            | `Super+1..9` (GlazeWM permite mais)       |
| `Super+Shift+1..4`      | Mover janela para workspace  | `Super+Shift+1..9`                        |
| `Super+Tab` / `+Shift`  | Próximo/anterior workspace   | igual                                     |
| `Super+Ctrl+Tab`        | Workspace anterior           | igual                                     |
| `Super+Ctrl+L`          | Bloquear tela                | igual (Windows já usa `Win+L` nativo também) |
| `Super+Ctrl+T`          | Monitor de atividade         | `Super+Ctrl+T` → Gerenciador de Tarefas   |
| `Super+Ctrl+D`          | Painel de tela               | `Super+Ctrl+D` → Config. de vídeo         |
| `Super+Ctrl+A`          | Painel de áudio              | `Super+Ctrl+A` → Config. de som           |
| `Super+Ctrl+P`          | Painel de energia            | `Super+Ctrl+P` → Config. de energia       |
| `Super+Shift+Return`    | Navegador                   | igual (abre o navegador padrão)           |
| `Super+Shift+F`         | Gerenciador de arquivos      | `Super+Shift+F` → Explorer                |
| `Super+Shift+N`         | Editor                      | `Super+Shift+N` → VS Code (troque à vontade) |
| `Super+Shift+R`         | Recarregar config            | igual                                     |

Sem equivalente direto no Windows (documentado, não forçado):

- `Super+Space` (menu do Omarchy) → o launcher aqui é o **PowerToys Run**.
  Configure o atalho dele para `Win+Space` em PowerToys → PowerToys Run →
  "Activation shortcut" (o padrão de fábrica é `Alt+Space`). Como o Windows
  usa `Win+Space` para trocar idioma de teclado por padrão, desative essa
  combinação em Configurações → Hora e idioma → Entrada → Atalhos de
  teclado avançados, ou o PowerToys Run não vai abrir.
- `Super+Escape` (menu do sistema) — sem painel equivalente nativo.
- `Ctrl+Alt+Del` (fechar todas as janelas) — combinação reservada pelo
  Windows (Secure Attention Sequence); nenhum app pode interceptá-la.
- `Super+C` / `Super+V` (copiar/colar) — o Windows já usa `Ctrl+C`/`Ctrl+V`
  globalmente; remapear quebraria o resto do sistema.

GlazeWM também ganha alguns atalhos extras que não existem no Omarchy
(`Super+M` minimizar, `Super+V` alternar direção de tiling, `Super+R` modo
de redimensionar, `Super+Shift+X` sair do GlazeWM) — todos comentados no
próprio `home/glazewm/config.yaml`.

## Instalação

Requer o **Modo de desenvolvedor** ativado (Configurações → Privacidade e
segurança → Para desenvolvedores) para criar os symlinks sem ser
administrador — mesma ideia do `omarchy.pl`, que também nunca altera nada
por padrão quando há um arquivo conflitante.

Ver o que seria feito, sem tocar em nada:

```powershell
pwsh ./dotfiles.ps1 -DryRun -All
```

Instalar preservando arquivos existentes em
`$env:USERPROFILE\.local\state\dotfiles\backups\`:

```powershell
pwsh ./dotfiles.ps1 -Backup
```

Desfazer, restaurando o backup mais recente sem apagar a cópia:

```powershell
pwsh ./dotfiles.ps1 -Restore
```

As etapas também rodam separadas com `-Fonts` (Lexend + JetBrainsMono Nerd
Font, per-user, sem admin), `-Theme` (color scheme do Windows Terminal,
wallpaper e o skin do Rainmeter recolorido) ou `-Apps` (`winget install` do
GlazeWM, Windows Terminal, PowerToys, Starship e Rainmeter). Para tudo de
uma vez:

```powershell
pwsh ./dotfiles.ps1 -All -Backup
```

`-Fonts`, `-Theme` e `-Apps` só rodam contra o `$HOME` real; `-Target` serve
apenas para testar a criação dos symlinks em outro diretório.

Se a criação de symlink falhar mesmo com o Modo de Desenvolvedor ativado no
registro (`AllowDevelopmentWithoutDevLicense`), o privilégio às vezes só
vale pra sessões interativas normais — sessões automatizadas/não
interativas podem não herdá-lo. Nesse caso, rode elevado:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-File .\dotfiles.ps1 -All -Backup'
```

## Widgets de desktop (Rainmeter)

Para a estética completa "HUD do SAO" na área de trabalho (equivalente
visual ao Feader-RSS do Omarchy), `dotfiles.ps1 -Theme` automatiza o
[SAO-Skin-Pack](https://github.com/rensatsu/SAO-Skin-Pack) — barras de
HP/CPU/RAM/disco/bateria e relógio no estilo SAO. Como o repositório está
arquivado desde 2019 sem licença explícita de redistribuição, o instalador
**não vendoriza** os arquivos dele neste repo: a cada instalação ele baixa
o pacote direto do GitHub para uma pasta temporária, aí sim recolore
localmente e copia o resultado para
`Documents\Rainmeter\Skins\Sword Art Online\` — o mesmo princípio do
`omarchy theme install <url>`, só que baixando na hora em vez de vendorizar.

O recolor é mecânico (matiz/saturação trocados pela cor-alvo, luz e sombra
originais preservadas — o mesmo efeito do modo "Colorize" do Photoshop),
não geração de imagem por IA:

- Barra de preenchimento "normal" (era verde) → accent ciano `#3ee8ff`
- Barra de preenchimento "crítico" (já era vermelho) → HP red `#ff3b5c`
- Moldura/trilha dos medidores → painel escuro `#16181b`, com a borda
  branca preservada
- Texto cinza dos widgets de RSS/notas → `#5c6670` (o mesmo `dark_foreground`
  do tema)

Depois de instalado, ative os skins pelo ícone do Rainmeter na bandeja em
*Skins → Sword Art Online → (CPU / RAM / Drive C / Drive D / Battery /
Clock / RSS)*.

## Atualizar o hardware

```powershell
pwsh ./scripts/hardware-profile.ps1            # mostra na tela
pwsh ./scripts/hardware-profile.ps1 -Save      # grava hardware/hardware-profile.txt
```

Diferente do `inxi -Fz` usado no Omarchy, esse script usa CIM/WMI
diretamente e nunca inclui e-mail de proprietário, chave de produto ou dados
de rede — só o necessário para decisões de configuração (CPU, RAM, GPU,
disco, bateria).
