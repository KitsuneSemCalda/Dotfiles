# Dotfiles para Omarchy — Samsung Book NP550XDA

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
`balanced` por padrão. Em carga baixa, o utilitário Perl incluído pode usar
`power-saver` automaticamente.

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
omarchy.pl                       # instalador e orquestrador, escrito em Perl
scripts/hardware-profile.pl     # atualiza o snapshot via inxi
```

Perl é usado para a automação e as ferramentas do repositório. Os arquivos
de configuração continuam em Lua/TOML porque são os formatos nativos do
Omarchy e do Hyprland.

Lexend é aplicada à interface por fontconfig e pelas configurações GTK; o
terminal continua usando JetBrainsMono Nerd Font, que é monoespaçada. Os
arquivos de Lexend são baixados pelo instalador e não são copiados para dentro
do repositório.

O perfil de aplicativos inclui Bitwarden, AppFlowy, PrismLauncher, CurseForge,
Amazon Shopping, Mercado Livre, Pinterest, Z Ai, WebMotors e Panini Brasil.
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
