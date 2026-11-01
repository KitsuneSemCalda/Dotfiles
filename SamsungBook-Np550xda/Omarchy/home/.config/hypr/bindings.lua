-- Atalhos pessoais ficam aqui; os atalhos padrão do Omarchy continuam ativos.
-- Antes de substituir um atalho existente, use:
--   omarchy menu keybindings --print
-- e remova-o com hl.unbind('SUPER + ...') antes de adicionar o novo.

-- Aplicativos removidos do perfil: HEY (e-mail/calendário) e 1Password.
hl.unbind('SUPER + SHIFT + C')
hl.unbind('SUPER + SHIFT + E')
hl.unbind('SUPER + SHIFT + ALT + E')
hl.unbind('SUPER + SHIFT + SLASH')

-- Keep the native menu available even if the optional Glass plugin is absent.
-- Super+Space uses the native menu; the Glass bar button keeps opening Glass.
