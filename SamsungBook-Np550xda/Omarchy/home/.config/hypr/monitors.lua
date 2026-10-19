-- Samsung NP550XDA-KF2BR: internal Full HD panel.
-- `preferred` keeps compatibility with external monitors connected later.
-- Scale 1 keeps the Full HD panel's native resolution; legibility is adjusted
-- via the font sizes defined elsewhere in the dotfiles.

local monitor_scale = 1

-- 1 is an integer value compatible with GTK and keeps the system scale
-- consistent with Hyprland.
hl.env('GDK_SCALE', tostring(monitor_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = monitor_scale })

-- O painel interno BOE NT156FHM-N61 tem gamut menor que sRGB. O perfil EDID
-- permite ao Hyprland converter as cores para as primárias reais do painel.
-- Keep this rule on one line: Omarchy's clamshell helper reads scale and
-- position from the eDP rule when it restores the panel after opening the lid.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = monitor_scale, cm = "edid" })
