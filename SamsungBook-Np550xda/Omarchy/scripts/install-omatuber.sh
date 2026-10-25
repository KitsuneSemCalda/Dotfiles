#!/usr/bin/env bash
set -euo pipefail

# main is only a placeholder; this is the reviewed implementation on dev.
revision=7a51920e8a6148ddf628f7ca1f35cab6be4682da
url=https://github.com/KitsuneForgering/OmaTuber.git
source_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/omatuber/source"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
install_root="${CARGO_HOME:-$HOME/.cargo}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

command -v cargo >/dev/null || { echo 'Cargo is required to build OmaTuber' >&2; exit 1; }
if [[ ! -d $source_dir/.git ]]; then
  mkdir -p -- "$(dirname -- "$source_dir")"
  git clone --depth 1 --branch dev --single-branch -- "$url" "$source_dir"
fi
[[ $(git -C "$source_dir" remote get-url origin) == "$url" ]] || {
  echo 'Unexpected OmaTuber checkout origin; preserved without changes' >&2; exit 1;
}
[[ -z $(git -C "$source_dir" status --porcelain) ]] || {
  echo 'OmaTuber checkout has local edits; preserved without changes' >&2; exit 1;
}
git -C "$source_dir" fetch --depth 1 origin "$revision"
git -C "$source_dir" checkout --detach "$revision"
[[ $(git -C "$source_dir" rev-parse HEAD) == "$revision" ]]

if [[ ! -x $install_root/bin/omatuber || ! -f $state_dir/omatuber-revision ]] \
    || [[ $(cat "$state_dir/omatuber-revision") != "$revision" ]]; then
  # Two compiler jobs bound memory use on the laptop. The default build uses
  # OBS audio meters; optional direct PipeWire sound classification is not needed.
  cargo install --locked --force --path "$source_dir" --bin omatuber --root "$install_root" --jobs 2
fi
install -Dm644 "$source_dir/packaging/omatuber.desktop" "$data_dir/applications/omatuber.desktop"
install -Dm644 "$source_dir/packaging/omatuber.svg" "$data_dir/icons/hicolor/scalable/apps/omatuber.svg"
mkdir -p -- "$state_dir"
printf '%s\n' "$revision" >"$state_dir/omatuber-revision"
