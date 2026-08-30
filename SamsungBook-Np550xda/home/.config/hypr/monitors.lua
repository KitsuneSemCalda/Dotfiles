-- Samsung NP550XDA-KF2BR: painel interno Full HD.
-- `preferred` mantém compatibilidade com monitores externos conectados depois.
-- Escala 1 evita custo visual e garante uma área útil confortável em 1920x1080.

local monitor_scale = 1

hl.env('GDK_SCALE', tostring(monitor_scale))
hl.monitor({
    output = '',
    mode = 'preferred',
    position = 'auto',
    scale = monitor_scale,
})
