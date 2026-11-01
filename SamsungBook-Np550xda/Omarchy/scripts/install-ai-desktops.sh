#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# The main installer has already downloaded and installed these packages.
# Keep the standalone command available for a focused migration.
if [[ -n ${DOTFILES_DOWNLOAD_MANIFEST:-} ]]; then
  pacman -Q claude-desktop >/dev/null
  pacman -Q chatgpt-bin &>/dev/null || pacman -Q chatgpt-desktop >/dev/null
else
# Keep the existing web launchers until both replacements are installed.
if ! pacman -Q chatgpt-bin &>/dev/null && ! pacman -Q chatgpt-desktop &>/dev/null; then
  omarchy pkg aur add chatgpt-desktop
fi

# Rebuild when the recipe is newer, so pkgver and pkgrel bumps reach this host.
recipe="$script_dir/../packages/claude-desktop/PKGBUILD"
# shellcheck disable=SC1090,SC2154 # The PKGBUILD defines pkgver and pkgrel.
wanted=$(source "$recipe" && printf '%s-%s' "$pkgver" "$pkgrel")
installed=$(pacman -Q claude-desktop 2>/dev/null) || installed=
installed=${installed#claude-desktop }
if [[ -z $installed ]] || (( $(vercmp "$installed" "$wanted") < 0 )); then
  [[ $(uname -m) == x86_64 ]] || {
    echo 'The pinned Claude Desktop recipe currently supports x86_64 only.' >&2
    exit 1
  }
  omarchy pkg add base-devel curl
  build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/claude-desktop"
  mkdir -p -- "$build_dir"
  cp -- "$recipe" "$build_dir/PKGBUILD"
  # This recipe only unpacks the official .deb; pacman resolves runtime deps.
  makepkg --dir "$build_dir" --nodeps --noconfirm --force
  mapfile -t packages < <(makepkg --dir "$build_dir" --packagelist)
  [[ ${#packages[@]} == 1 && -f ${packages[0]} ]] || {
    echo 'Expected one built Claude Desktop package.' >&2
    exit 1
  }
  pkexec pacman -U --needed --noconfirm -- "${packages[0]}"
fi

fi

command -v chatgpt >/dev/null
command -v claude-desktop >/dev/null
pacman -Q claude-desktop >/dev/null
pacman -Q chatgpt-bin &>/dev/null || pacman -Q chatgpt-desktop >/dev/null

for name in ChatGPT Claude; do
  launcher="$HOME/.local/share/applications/$name.desktop"
  if [[ -f $launcher ]] && grep -qE '^Exec=.*(omarchy-launch-webapp|omarchy-webapp-handler)' "$launcher"; then
    omarchy webapp remove "$name"
  fi
done
