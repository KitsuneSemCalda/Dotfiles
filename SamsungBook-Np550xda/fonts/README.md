# Lexend

Este dotfiles usa Lexend como fonte sans-serif da interface (apps GTK/Qt,
menus e a barra do Omarchy). Ela é distribuída pelo [Google Fonts](https://fonts.google.com/specimen/Lexend)
e foi desenhada com base em pesquisa sobre fluidez de leitura, priorizando
conforto visual em textos longos — substitui a Source Sans 3 usada antes.

A fonte monoespaçada dos terminais (Alacritty/Kitty/Ghostty/Foot) continua
separada, gerenciada por `omarchy font set <nome>` (ver `omarchy font list`
/ `omarchy font current`). Lexend é proporcional, então não é usada como
fonte de terminal — misturar as duas mantém o texto de código/tabelas
alinhado.

O `fonts.conf` também define um piso de acessibilidade: nenhuma fonte
renderiza abaixo de 18pt, mesmo que o app peça um tamanho menor (o
`gtk-font-name` já usa 18 diretamente, então essa regra cobre outros apps
GTK/Qt/Pango que pedem tamanhos menores). Terminais ficam de fora, já que
definem o tamanho fora do fontconfig.

Não existe pacote Lexend no repositório oficial do Arch nem no AUR. Os
arquivos da fonte não são versionados aqui; o comando abaixo baixa os pesos
Regular e Bold diretamente da API do Google Fonts para
`~/.local/share/fonts/lexend/` e ativa as regras de fontconfig/GTK deste
repositório:

```bash
perl ./omarchy.pl --fonts --backup
```
