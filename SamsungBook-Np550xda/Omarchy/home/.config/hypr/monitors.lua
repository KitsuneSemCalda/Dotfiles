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

-- Samsung SMB2030N on the desk: preferred EDID timing is 1600x900 at 60 Hz.
-- Match the display identity so the rule survives HDMI connector renumbering.
-- Keep SDR sRGB and 8-bit output; no measured ICC profile is available.
hl.monitor({ output = "desc:Samsung Electric Company SMB2030N HXOZB03691", mode = "1600x900@60", position = "auto", scale = 1, transform = 0, bitdepth = 8, cm = "srgb", vrr = 0 })

-- The desk HDMI-to-VGA adapter substitutes a generic EDID (preferred 1024x768).
-- This identity belongs to that adapter, not to the Samsung panel. Keep its
-- native 1600x900 timing explicit while this adapter drives the B2030N.
hl.monitor({ output = "desc:RGT 0x1352 0x01010101", mode = "1600x900@60", position = "auto", scale = 1, transform = 0, bitdepth = 8, cm = "srgb", vrr = 0 })
