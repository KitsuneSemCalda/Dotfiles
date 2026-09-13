# Dotfiles para Omarchy — Samsung Book NP550XDA

Veja também a [análise de arquitetura e diagramas](../docs/arquitetura.md),
com as modificações sobre a base e os limites dos instaladores.

Base inicial de dotfiles para o Samsung NP550XDA-KF2BR, rodando Omarchy com
Hyprland. O snapshot completo usado para tomar as decisões está em
[`hardware/inxi-Fz.txt`](hardware/inxi-Fz.txt).

## Perfil da máquina

- Intel Core i5-1135G7, 4 núcleos / 8 threads
- 16 GiB de RAM
- Intel Iris Xe (`i915`)
- Tela interna 1920×1080
- NVMe Samsung de aproximadamente 256 GiB
- Bateria com capacidade observada em 30,7% da capacidade de projeto
- Sistema de arquivos Btrfs com swapfile e zram

As escolhas iniciais seguem esse perfil: escala 1 e fontes de interface e
terminal em tamanho 20, além do modo de monitor
`preferred`, efeitos visuais moderados para a Iris Xe e perfil de energia
`balanced` por padrão. Ao iniciar a sessão, o utilitário Perl incluído seleciona
`power-saver` se a bateria estiver descarregando com carga de até 25%;
nos demais casos, seleciona `balanced`. Não há monitoramento contínuo.

## Estrutura

```text
home/
├── .config/
│   ├── alacritty/alacritty.toml
│   ├── btop/btop.conf
│   ├── fontconfig/fonts.conf   # Lexend como sans-serif
│   ├── gtk-3.0/settings.ini
│   ├── gtk-4.0/settings.ini
│   ├── hypr/                   # configuração Lua nativa do Omarchy
│   ├── omarchy/rss-reader.json # feeds do Feader-RSS
│   ├── omarchy/shell.toml      # tamanho-base da interface do Omarchy
│   └── starship.toml
└── .local/bin/
    └── omarchy-power-profile  # ajuste de energia escrito em Perl
hardware/
└── inxi-Fz.txt
docker/
├── docker-compose.yml           # postgres, redis, frankmd, ai-memory, pihole
└── .env.example                 # variáveis documentadas (.env real fica fora do git)
omarchy.pl                       # instalador e orquestrador, escrito em Perl
scripts/hardware-profile.pl     # atualiza o snapshot via inxi
scripts/docker-stack.pl         # sobe a stack Docker e liga os agentes de IA
```

Perl é usado para a automação e as ferramentas do repositório. Os arquivos
de configuração continuam em Lua/TOML porque são os formatos nativos do
Omarchy e do Hyprland.

Lexend é aplicada à interface por fontconfig e pelas configurações GTK; o
terminal continua usando JetBrainsMono Nerd Font, que é monoespaçada. Os
arquivos de Lexend são baixados pelo instalador e não são copiados para dentro
do repositório.

O perfil de aplicativos inclui Bitwarden, AppFlowy, PrismLauncher, CurseForge,
Amazon Shopping, Mercado Livre, Pinterest, Z Ai, WebMotors, Panini Brasil,
GitHub, GitLab e Codeberg.
Também registra o tema [Sword Art Omarchy](https://github.com/KitsuneSemCalda/Sword-Art-Omarchy)
e o plugin [Feader-RSS](https://github.com/KitsuneSemCalda/Feader-RSS), com a
configuração de feeds em `~/.config/omarchy/rss-reader.json`.

## Instalação

O instalador não altera nada por padrão quando há um arquivo conflitante. Veja
primeiro o que seria feito:

```bash
perl ./omarchy.pl --dry-run
```

Para instalar preservando arquivos existentes em
`~/.local/state/dotfiles/backups/`:

```bash
perl ./omarchy.pl --backup
```

Para desfazer a instalação, restaurando o backup mais recente sem apagar sua
cópia:

```bash
perl ./omarchy.pl --restore
```

O restore só substitui symlinks que ainda apontam para este repositório (ou
cria arquivos que estejam ausentes). Se encontrar alterações manuais no
destino, aborta a operação inteira para evitar sobrescrevê-las. Use
`--restore --dry-run` para conferir o backup escolhido antes de restaurar.

As etapas também podem ser executadas separadamente com `--fonts`, `--apps`,
`--plugin` ou `--theme`. `--apps` usa os repositórios oficiais para
PrismLauncher e os pacotes AUR para Bitwarden, AppFlowy e CurseForge.

Para aplicar também fontes, aplicativos, plugin e tema — incluindo operações
de rede e possíveis prompts de senha do gerenciador de pacotes:

```bash
perl ./omarchy.pl --all --backup
```

O instalador cria symlinks para os arquivos dentro de `home/`. Nenhuma
configuração do sistema foi alterada ao criar este repositório; `--all` é a
opção que aplica as mudanças externas.

## Stack Docker

`docker/docker-compose.yml` sobe cinco serviços, todos publicados só em
`127.0.0.1` (nenhum fica acessível pela rede local):

- **postgres** (17-alpine) e **redis** (7-alpine) — banco e cache de uso
  geral para projetos locais, portas `5432` e `6379`.
- **[FrankMD](https://github.com/akitaonrails/FrankMD)** — editor de notas
  Markdown self-hosted, porta `7591`, guarda os arquivos em
  `~/Documents/notes` (sem banco de dados).
- **[ai-memory](https://github.com/akitaonrails/ai-memory)** — memória
  persistente entre agentes de IA, porta `49374`.
- **pihole** — DNS local, porta `53` e UI de administração em `8080`.

Primeira execução (cria `docker/.env` com segredos aleatórios, a pasta de
notas e sobe os containers):

```bash
perl scripts/docker-stack.pl --up
```

Ligar o ai-memory a todos os agentes de IA já instalados (hoje detecta
`claude`, `codex`, `gemini`, `cursor-agent`, `opencode` e `grok` no `PATH`,
via `install-mcp`/`install-hooks`):

```bash
perl scripts/docker-stack.pl --agents
```

Tornar o Pi-hole o DNS padrão desta máquina (espera o container ficar
saudável antes de aplicar; delega para `omarchy dns Custom` com
`127.0.0.1` e fallback `1.1.1.1`, que é o mecanismo nativo do Omarchy — evita
reimplementar via `nmcli` direto, que nesta máquina também gerencia as
bridges do Docker e pode derrubar o encaminhamento de pacotes dos
containers se mexido diretamente):

```bash
perl scripts/docker-stack.pl --dns
```

`omarchy dns` (sem argumento) pode mostrar "Cloudflare" mesmo com o Pi-hole
ativo — a detecção dele olha só se `1.1.1.1` aparece na lista, que é
justamente o fallback. Confirme o servidor real com `resolvectl status`
(`Current DNS Server: 127.0.0.1`).

Reverter o DNS para automático (`omarchy dns DHCP`), parar a stack ou só
conferir o estado dos containers:

```bash
perl scripts/docker-stack.pl --dns-revert
perl scripts/docker-stack.pl --down
perl scripts/docker-stack.pl --status
```

Qualquer ação aceita `--dry-run`. As chaves de API opcionais do ai-memory
(resumo por LLM e busca semântica) ficam em branco em `docker/.env` até
serem preenchidas manualmente; sem elas, a memória funciona só com busca
por texto.

## Atualizar o hardware

O relatório pode ser apenas exibido:

```bash
perl scripts/hardware-profile.pl
```

Para substituir o snapshot versionado com uma nova coleta de `inxi -Fz`:

```bash
perl scripts/hardware-profile.pl --save
```

Depois de instalar ou alterar arquivos Lua do Hyprland, valide no ambiente
gráfico com `hyprctl reload` e `hyprctl configerrors`, conforme a documentação
do Omarchy.
