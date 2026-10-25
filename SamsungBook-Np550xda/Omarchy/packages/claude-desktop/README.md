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
