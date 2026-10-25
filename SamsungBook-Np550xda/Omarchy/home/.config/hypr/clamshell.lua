-- Apply at configuration load, after hardware overrides and saved toggles.
-- The helper reads the lid and DRM connectors without requiring a running
-- compositor, so this also works during Hyprland's initial configuration.
local clamshell = os.execute('omarchy-hw-clamshell >/dev/null 2>&1')
if clamshell == true or clamshell == 0 then
  hl.monitor({ output = "eDP-1", disabled = true })
end
