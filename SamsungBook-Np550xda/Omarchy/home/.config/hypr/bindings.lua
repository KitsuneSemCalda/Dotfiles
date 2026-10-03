-- Atalhos pessoais ficam aqui; os atalhos padrão do Omarchy continuam ativos.
-- Antes de substituir um atalho existente, use:
--   omarchy menu keybindings --print
-- e remova-o com hl.unbind('SUPER + ...') antes de adicionar o novo.

-- Aplicativos removidos do perfil: HEY (e-mail/calendário) e 1Password.
hl.unbind('SUPER + SHIFT + C')
hl.unbind('SUPER + SHIFT + E')
hl.unbind('SUPER + SHIFT + ALT + E')
hl.unbind('SUPER + SHIFT + SLASH')

-- omarchy-liquid-glass >>>
o.bind("SUPER + CTRL + G", "Glass Tuner", "python3 " .. string.format("%q", os.getenv("HOME") .. "/.local/share/omarchy-liquid-glass/tuner/tuner.py"))
-- <<< omarchy-liquid-glass
