#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
app_name="Barkeep"
bundle_id="${BUNDLE_ID:-is.ian.barkeep}"
requested_build_number="${BUILD_NUMBER:-}"
source "$repo_dir/version.env"
version="${VERSION:-$MARKETING_VERSION}"
build_number="${requested_build_number:-$BUILD_NUMBER}"
sign_identity="${SIGN_IDENTITY:-}"
signing_identity_file="${SIGNING_IDENTITY_FILE:-$repo_dir/.signing-identity}"
team_id="${DEVELOPMENT_TEAM:-JXNCT3BEVQ}"
configuration="${CONFIGURATION:-Release}"
derived_dir="$repo_dir/.xcode-build"
source_app="$derived_dir/Build/Products/$configuration/$app_name.app"
dist_dir="$repo_dir/dist"
dist_app="$dist_dir/$app_name.app"
entitlements="$repo_dir/Sources/Barkeep/Barkeep.entitlements"

cd "$repo_dir"

if [[ -z "$sign_identity" && -f "$signing_identity_file" ]]; then
    IFS= read -r sign_identity < "$signing_identity_file"
fi

if [[ -z "$sign_identity" ]]; then
    sign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/^[^"]*"\([^"]*\)".*$/\1/p' \
            | sed -n '/^Developer ID Application: /{p;q;}'
    )"
fi

if [[ -z "$sign_identity" ]]; then
    sign_identity="-"
    echo "warning: no Developer ID identity was found; macOS permissions can reset" >&2
fi

xcodegen generate

build_settings=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$sign_identity"
    DEVELOPMENT_TEAM="$team_id"
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id"
    MARKETING_VERSION="$version"
    CURRENT_PROJECT_VERSION="$build_number"
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
)

if [[ "$sign_identity" == "-" ]]; then
    build_settings+=(ENABLE_HARDENED_RUNTIME=NO)
fi

xcodebuild build \
    -quiet \
    -project Barkeep.xcodeproj \
    -scheme Barkeep \
    -configuration "$configuration" \
    -derivedDataPath "$derived_dir" \
    -destination 'generic/platform=macOS' \
    "${build_settings[@]}"

if [[ ! -d "$source_app" ]]; then
    echo "$source_app was not produced" >&2
    exit 66
fi

mkdir -p "$dist_dir"
if [[ -e "$dist_app" ]]; then
    case "$dist_app" in
        "$dist_dir/$app_name.app") rm -rf "$dist_app" ;;
        *) echo "refusing to replace unexpected path: $dist_app" >&2; exit 70 ;;
    esac
fi
ditto "$source_app" "$dist_app"

sign_flags=(--force)
if [[ "$sign_identity" != "-" ]]; then
    sign_flags+=(--options runtime --timestamp)
fi

codesign "${sign_flags[@]}" --entitlements "$entitlements" \
    --sign "$sign_identity" "$dist_app"

codesign --verify --deep --strict --verbose=2 "$dist_app"

if [[ "$sign_identity" != "-" ]]; then
    sign_info="$(codesign -d --verbose=4 "$dist_app" 2>&1 || true)"
    if [[ "$sign_info" != *"Authority=Developer ID Application:"* || \
          "$sign_info" != *"Timestamp="* ]]; then
        echo "$dist_app does not have a timestamped Developer ID signature" >&2
        exit 65
    fi

    if codesign -d --entitlements :- "$dist_app" 2>/dev/null \
        | plutil -extract com.apple.security.get-task-allow raw -o - - 2>/dev/null \
        | grep -qx true; then
        echo "$dist_app contains the debug get-task-allow entitlement" >&2
        exit 65
    fi
fi

echo "Built $dist_app"
echo "Signed with: $sign_identity"
