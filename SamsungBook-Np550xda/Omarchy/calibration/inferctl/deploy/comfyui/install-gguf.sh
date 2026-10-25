#!/usr/bin/env bash
set -euo pipefail
revision=6ea2651e7df66d7585f6ffee804b20e92fb38b8a
checksum=688126d5c2b8c4ff061f56b23c3c6791ac01dc366e98d41ef1aaef374c36f283
node_root="${COMFY_DATA:-$HOME/.local/share/inferctl/comfyui}/custom_nodes"
destination="$node_root/ComfyUI-GGUF"
if [[ -e "$destination" ]]; then
  echo "Already exists; refusing overwrite: $destination" >&2
  exit 1
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
curl -fL "https://codeload.github.com/city96/ComfyUI-GGUF/tar.gz/$revision" -o "$scratch/node.tar.gz"
printf '%s  %s\n' "$checksum" "$scratch/node.tar.gz" | sha256sum --check
mkdir "$scratch/node"
tar -xzf "$scratch/node.tar.gz" --strip-components=1 -C "$scratch/node"
mkdir -p "$node_root"
mv "$scratch/node" "$destination"
printf 'Installed ComfyUI-GGUF %s in %s\n' "$revision" "$destination"
