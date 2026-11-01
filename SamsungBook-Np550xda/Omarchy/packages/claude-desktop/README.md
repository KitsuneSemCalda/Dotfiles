# Claude Desktop no Omarchy

O arquivo `claude-desktop_amd64.deb` é a versão 3.1623.0 do Claude Desktop
para Debian/Ubuntu. O Omarchy usa Arch Linux e `pacman` não instala `.deb`
diretamente. Este `PKGBUILD` baixa o arquivo oficial e o transforma em um pacote Arch
rastreado pelo `pacman`. Não coloque o `.deb` no Git.

## Instalar esta versão

Execute a partir desta pasta:

```bash
makepkg
pkexec pacman -U -- ./claude-desktop-*.pkg.tar.zst
claude-desktop
```

O `pacman -U` instala o pacote final e resolve as dependências pelos
repositórios Arch após a autorização do `pkexec`. Também é possível abrir Claude
pelo menu de aplicativos. O pacote extraído já traz o lançador `.desktop`.

O `.deb` oficial instala `/usr/bin/claude-desktop` como link direto para o
binário. Fora do GNOME e do KDE, o Electron não usa o GNOME Keyring e grava
login e segredos em texto puro; o Claude então mostra o aviso "No system
keyring is available". Esta receita troca o link por um script que adiciona
`--password-store=gnome-libsecret`, a menos que outro `--password-store` já
tenha sido passado. Reinicie o Claude por completo depois de atualizar o pacote.
Os dotfiles também instalam `~/.config/chatgpt-flags.conf` e
`~/.config/electron-flags.conf` com a mesma opção, para o ChatGPT Desktop e os
apps que usam o Electron do sistema, como o Obsidian. O comando `check-keyring`
confere o GNOME Keyring, o lançador do Claude e esses dois arquivos.

Para saber se a Anthropic publicou uma versão mais nova, execute
`python3 ../../scripts/check-claude-desktop-version.py` a partir desta pasta. Ele
mostra o `pkgver` e o `sha256sums` a usar. Um workflow semanal do GitHub
Actions roda a mesma verificação e falha quando a receita fica para trás.

Para remover:

```bash
pkexec pacman -Rns claude-desktop
```

Para uma versão futura, confirme a URL do novo `.deb`, atualize `pkgver` e
`sha256sums` no `PKGBUILD`, depois execute `makepkg` e `pkexec pacman -U` novamente. Uma
instalação feita com este arquivo local não recebe atualizações automáticas.

O suporte oficial da Anthropic para Linux ainda cobre Debian e Ubuntu. No
Omarchy, o funcionamento de alguns recursos pode variar. O Cowork requer
virtualização KVM, QEMU e firmware UEFI; esses pacotes constam como
dependências opcionais nesta receita.
