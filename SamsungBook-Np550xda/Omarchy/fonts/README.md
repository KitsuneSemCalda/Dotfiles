# Lexend

These dotfiles use Lexend as the interface's sans-serif font (GTK/Qt apps,
menus, and the Omarchy bar). It's distributed by [Google Fonts](https://fonts.google.com/specimen/Lexend)
and is downloaded by the font installer.

The terminals' monospaced font remains separate. Omarchy provides font controls
through `omarchy font set <name>` (see `omarchy font list`
/ `omarchy font current`); this repository specifies the font in its Alacritty
and Foot profiles and does not ship Kitty or Ghostty configuration.
Lexend is proportional, so it isn't used as
a terminal font, keeping code/table text
aligned.

`fonts.conf` requests a minimum size of 20 for applications that use its rules;
`gtk-font-name` also uses 20 directly. Applications can bypass fontconfig.
The shell has its own base size of 14, while the versioned Alacritty and Foot
profiles use JetBrainsMono Nerd Font at size 11. These settings do not guarantee
the same physical text size across applications.

The font files are not versioned here; the command below downloads the
Regular and Bold weights directly from the Google Fonts API to
`~/.local/share/fonts/lexend/` and enables this repository's
fontconfig/GTK rules:

```bash
perl ./omarchy.pl --fonts --backup
```
