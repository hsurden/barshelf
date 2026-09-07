#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
app_name="BarShelf"
source_app="$repo_dir/dist/$app_name.app"
install_dir="${INSTALL_DIR:-$HOME/Applications}"
installed_app="$install_dir/$app_name.app"
trash_dir="$HOME/.Trash"

"$repo_dir/scripts/build-local-clt.sh"
mkdir -p "$install_dir" "$trash_dir"

# Only these two exact personal-fork paths are eligible. The signed upstream
# /Applications/Barkeep.app is deliberately untouched.
pkill -f "$source_app/Contents/MacOS/$app_name" 2>/dev/null || true
pkill -f "$installed_app/Contents/MacOS/$app_name" 2>/dev/null || true

if [[ -e "$installed_app" ]]; then
    case "$installed_app" in
        "$install_dir/$app_name.app")
            timestamp="$(date +%Y%m%d-%H%M%S)"
            backup="$trash_dir/$app_name previous $timestamp.app"
            mv "$installed_app" "$backup"
            echo "Moved the previous installed app to $backup"
            ;;
        *) echo "refusing to replace unexpected path: $installed_app" >&2; exit 70 ;;
    esac
fi

ditto "$source_app" "$installed_app"
xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$installed_app"
open -n "$installed_app"

echo "Installed and opened $installed_app"
