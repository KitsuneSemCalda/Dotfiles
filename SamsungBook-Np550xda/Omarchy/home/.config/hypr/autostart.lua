-- Personal autostart overrides.
--
-- Omarchy's own default autostart (loaded earlier via default.hypr.omarchy)
-- already runs `omarchy-powerprofiles-init` on every session start, which
-- picks the profile from the AC/battery signal (UPower) and remembers the
-- user's choice per state. A previous version of this file duplicated that
-- with a hand-rolled Perl script calling `powerprofilesctl` directly, using a
-- cruder battery-percentage heuristic that ran right after and overrode the
-- omarchy CLI's own decision. Removed: there is nothing left to add here.

-- omarchy-liquid-glass >>>
-- load hyprpm plugins (HyprGlass Liquid), then re-read the config so liquid_glass.lua sees it
o.launch_on_start("sh -c 'hyprpm reload -n; hyprctl reload'")
-- <<< omarchy-liquid-glass
