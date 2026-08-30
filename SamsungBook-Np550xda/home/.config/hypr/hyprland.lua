-- Configuração principal do Hyprland para Omarchy.
-- Os defaults do Omarchy são carregados primeiro; os arquivos abaixo são
-- sobreposições pessoais e podem ser atualizados independentemente.

dofile((os.getenv('OMARCHY_PATH') or '/usr/share/omarchy') .. '/default/hypr/bootstrap.lua')

require('default.hypr.omarchy')

require('hypr.monitors')
require('hypr.input')
require('hypr.bindings')
require('hypr.looknfeel')
require('hypr.autostart')

require('default.hypr.toggles')


-- [key-visualizer] capture hook (managed by the plugin; safe to remove)
local kc_path = os.getenv("HOME") .. "/.config/omarchy/plugins/felixzsh.key-visualizer/key-visualizer.lua"
local kc_file = io.open(kc_path, "r")
if kc_file then kc_file:close(); dofile(kc_path) end
