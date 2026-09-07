#!/bin/zsh

# Regenerate the macOS icon representations from the approved PNG artwork.
set -euo pipefail

repo_dir="${0:A:h:h}"
resources_dir="$repo_dir/Sources/BarShelf/Resources"
icon_work_dir="$(mktemp -d)"
trap 'rm -rf "$icon_work_dir"' EXIT
iconset_dir="$icon_work_dir/AppIcon.iconset"
mkdir -p "$iconset_dir"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$resources_dir/AppIcon.png" \
        --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$resources_dir/AppIcon.png" \
        --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset_dir" -o "$resources_dir/AppIcon.icns"
echo "Built $resources_dir/AppIcon.icns"
