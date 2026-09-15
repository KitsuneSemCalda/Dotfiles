-- The external Dareu EK75 keyboard is US/ANSI; keeping intl global avoids
-- losing accented characters while it's connected.

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

-- Three-finger gesture to switch workspace on the touchpad.
hl.gesture({ fingers = 3, direction = 'horizontal', action = 'workspace' })

-- Built-in keyboard of the Samsung Book NP550XDA-KF2BR (ABNT2).
hl.device({
    name = 'at-translated-set-2-keyboard',
    kb_layout = 'br',
    kb_variant = 'abnt2',
})

-- The names below correspond to the two interfaces observed for the EK75.
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
