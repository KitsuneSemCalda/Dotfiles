-- Efeitos moderados para a Intel Iris Xe: visual agradável sem exigir blur
-- pesado de uma GPU dedicada, importante também para a autonomia da bateria.

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 1,
    },

    decoration = {
        rounding = 8,

        shadow = {
            enabled = true,
            range = 12,
            render_power = 2,
            color = 'rgba(00000033)',
        },

        blur = {
            enabled = true,
            size = 4,
            passes = 2,
            new_optimizations = true,
        },
    },
})
