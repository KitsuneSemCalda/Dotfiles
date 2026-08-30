-- O teclado externo Dareu EK75 é US/ANSI; manter intl global evita perder
-- acentos quando ele estiver conectado.

hl.config({
    input = {
        kb_layout = 'us',
        kb_variant = 'intl',
        kb_options = 'compose:caps',

        repeat_rate = 40,
        repeat_delay = 250,
        numlock_by_default = true,
        sensitivity = 0.3,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
        },
    },
})

-- Gesto de três dedos para trocar de workspace no touchpad.
hl.gesture({ fingers = 3, direction = 'horizontal', action = 'workspace' })

-- Teclado embutido do Samsung Book NP550XDA-KF2BR (ABNT2).
hl.device({
    name = 'at-translated-set-2-keyboard',
    kb_layout = 'br',
    kb_variant = 'abnt2',
})

-- Os nomes abaixo correspondem às duas interfaces observadas para o EK75.
hl.device({
    name = 'ek75_keyboard-1',
    kb_layout = 'us',
    kb_variant = 'intl',
})
hl.device({
    name = 'ek75_keyboard-2',
    kb_layout = 'us',
    kb_variant = 'intl',
})
