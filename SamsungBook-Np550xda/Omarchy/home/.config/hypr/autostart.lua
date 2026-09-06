-- A bateria observada está com cerca de 30,7% da capacidade original.
-- Se o utilitário Perl estiver instalado, ele escolhe balanced ou power-saver
-- de acordo com a carga atual; caso contrário, mantemos o fallback simples.

local home = os.getenv('HOME')
local profile_script = home and (home .. '/.local/bin/omarchy-power-profile') or nil
local script_file = profile_script and io.open(profile_script, 'r') or nil

if script_file then
    script_file:close()
    o.launch_on_start(string.format('perl %q', profile_script))
else
    o.launch_on_start('powerprofilesctl set balanced')
end
