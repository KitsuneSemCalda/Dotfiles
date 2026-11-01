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

`fonts.conf` selects Lexend without forcing a global minimum size. GTK and the
shell use size 14, while Alacritty and Foot use JetBrainsMono Nerd Font at size
11. These settings do not guarantee identical physical text size across apps.

The font files are not versioned here. The main installer first downloads the
Regular and Bold TTFs into its unified download cache. Only after all selected
downloads succeed does it copy them to `~/.local/share/fonts/lexend/`, refresh
fontconfig and publish the font configuration:

```bash
perl ./omarchy.pl --fonts --backup
```
