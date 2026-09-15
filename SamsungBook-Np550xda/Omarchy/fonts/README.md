# Lexend

These dotfiles use Lexend as the interface's sans-serif font (GTK/Qt apps,
menus, and the Omarchy bar). It's distributed by [Google Fonts](https://fonts.google.com/specimen/Lexend)
and was designed based on research into reading fluency, prioritizing
visual comfort in long text — it replaces the Source Sans 3 used previously.

The terminals' monospaced font (Alacritty/Kitty/Ghostty/Foot) remains
separate, managed by `omarchy font set <name>` (see `omarchy font list`
/ `omarchy font current`). Lexend is proportional, so it isn't used as
a terminal font — keeping the two separate keeps code/table text
aligned.

`fonts.conf` also defines an accessibility floor: no font
renders below 20pt, even if the app requests a smaller size (the
`gtk-font-name` already uses 20 directly, so this rule covers other
GTK/Qt/Pango apps that request smaller sizes). Terminals are excluded, since
they set their size outside of fontconfig.

There is no Lexend package in the official Arch repositories or the AUR. The
font files are not versioned here; the command below downloads the
Regular and Bold weights directly from the Google Fonts API to
`~/.local/share/fonts/lexend/` and enables this repository's
fontconfig/GTK rules:

```bash
perl ./omarchy.pl --fonts --backup
```
