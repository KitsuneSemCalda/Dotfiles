#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Keep the existing web launchers until both replacements are installed.
if ! pacman -Q chatgpt-bin &>/dev/null && ! pacman -Q chatgpt-desktop &>/dev/null; then
  omarchy pkg aur add chatgpt-desktop
fi

if ! pacman -Q claude-desktop &>/dev/null; then
  [[ $(uname -m) == x86_64 ]] || {
    echo 'The pinned Claude Desktop recipe currently supports x86_64 only.' >&2
    exit 1
  }
  omarchy pkg add base-devel curl
  build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/claude-desktop"
  mkdir -p -- "$build_dir"
  cp -- "$script_dir/../packages/claude-desktop/PKGBUILD" "$build_dir/PKGBUILD"
  # This recipe only unpacks the official .deb; pacman resolves runtime deps.
  makepkg --dir "$build_dir" --nodeps --noconfirm --force
  mapfile -t packages < <(makepkg --dir "$build_dir" --packagelist)
  [[ ${#packages[@]} == 1 && -f ${packages[0]} ]] || {
    echo 'Expected one built Claude Desktop package.' >&2
    exit 1
  }
  pkexec pacman -U --needed --noconfirm -- "${packages[0]}"
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
