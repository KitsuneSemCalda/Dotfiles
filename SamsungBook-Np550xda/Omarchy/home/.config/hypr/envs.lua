local paths = require("default.hypr.paths")

-- Flatpak's own systemd generator only sets XDG_DATA_DIRS at login, so an
-- app installed mid-session (e.g. via flatpak install) won't show up in the
-- launcher or the icon search path until this is set explicitly.
hl.env(
  "XDG_DATA_DIRS",
  paths.home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
)
