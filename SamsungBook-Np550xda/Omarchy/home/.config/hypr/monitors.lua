-- Samsung NP550XDA-KF2BR: painel interno Full HD.
-- `preferred` mantém compatibilidade com monitores externos conectados depois.
-- Escala 1 mantém a área nativa do painel Full HD; a legibilidade é ajustada
-- pelos tamanhos de fonte definidos no restante do dotfiles.

local monitor_scale = 1

-- 1 é um valor inteiro compatível com GTK e mantém a escala do sistema
-- consistente com o Hyprland.
hl.env('GDK_SCALE', tostring(monitor_scale))
hl.monitor({
    output = '',
    mode = 'preferred',
    position = 'auto',
    scale = monitor_scale,
})
