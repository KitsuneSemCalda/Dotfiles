-- Main Hyprland configuration for Omarchy.
-- Omarchy's defaults are loaded first; the files below are personal
-- overrides and can be updated independently.

dofile((os.getenv('OMARCHY_PATH') or '/usr/share/omarchy') .. '/default/hypr/bootstrap.lua')

require('default.hypr.omarchy')

require('hypr.envs')
require('hypr.monitors')
require('hypr.input')
require('hypr.bindings')
require('hypr.looknfeel')
require('hypr.autostart')
require('hypr.windows')

require('default.hypr.toggles')


-- [key-visualizer] capture hook (managed by the plugin; safe to remove)
local kc_path = os.getenv("HOME") .. "/.config/omarchy/plugins/felixzsh.key-visualizer/key-visualizer.lua"
local kc_file = io.open(kc_path, "r")
if kc_file then kc_file:close(); dofile(kc_path) end
