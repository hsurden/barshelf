#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
source "$repo_dir/version.env"

app_name="BarShelf"
bundle_id="com.hsurden.barshelf"
dist_dir="$repo_dir/dist"
app_path="$dist_dir/$app_name.app"
contents_dir="$app_path/Contents"
executable_path="$contents_dir/MacOS/$app_name"
info_path="$contents_dir/Info.plist"
entitlements="$repo_dir/Sources/BarShelf/BarShelf.entitlements"

cd "$repo_dir"

if [[ -e "$app_path" ]]; then
    case "$app_path" in
        "$dist_dir/$app_name.app") rm -r "$app_path" ;;
        *) echo "refusing to replace unexpected path: $app_path" >&2; exit 70 ;;
    esac
fi

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

swiftc -O \
    $(find Sources/BarShelf -name '*.swift' -print | sort) \
    -o "$executable_path"

cp Sources/BarShelf/Info.plist "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $app_name" "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $app_name" "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$info_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$info_path"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$info_path"

# A stable local identity keeps the TCC Accessibility grant across rebuilds,
# because macOS then matches the certificate instead of each build's cdhash.
# Create it once: self-signed "BarShelf Signing" cert trusted for codeSign.
local_identity="BarShelf Signing"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$local_identity"; then
    # The certificate created for the app's earlier name still works; only
    # its display name is old. Create "BarShelf Signing" to retire it.
    local_identity="Barkeep HS Signing"
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$local_identity"; then
    codesign --force --deep --sign "$local_identity" --entitlements "$entitlements" "$app_path"
    echo "Signed with the stable local identity: $local_identity"
else
    codesign --force --deep --sign - --entitlements "$entitlements" "$app_path"
    echo "Signed ad-hoc. This build can require Accessibility permission again after rebuilding."
fi
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Built $app_path"
