local paths = require("default.hypr.paths")

-- Flatpak's own systemd generator only sets XDG_DATA_DIRS at login, so an
-- app installed mid-session (e.g. via flatpak install) won't show up in the
-- launcher or the icon search path until this is set explicitly.
hl.env(
  "XDG_DATA_DIRS",
  paths.home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
)

-- Use the same dead-key composition in native Wayland, GTK and Qt apps.
hl.env("XCOMPOSEFILE", paths.home .. "/.XCompose")
hl.env("GTK_IM_MODULE", "simple")
hl.env("QT_IM_MODULE", "compose")
