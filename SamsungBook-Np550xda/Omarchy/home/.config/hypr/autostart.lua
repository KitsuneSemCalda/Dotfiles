-- The observed battery is at roughly 30.7% of its original capacity.
-- If the Perl utility is installed, it picks balanced or power-saver
-- based on the current charge; otherwise we keep the simple fallback.

local home = os.getenv('HOME')
local profile_script = home and (home .. '/.local/bin/omarchy-power-profile') or nil
local script_file = profile_script and io.open(profile_script, 'r') or nil

if script_file then
    script_file:close()
    o.launch_on_start(string.format('perl %q', profile_script))
else
    o.launch_on_start('powerprofilesctl set balanced')
end
