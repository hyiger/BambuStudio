#!/bin/bash
# Package a built BambuStudio.app into a compressed, drag-to-install DMG.
#
# Usage: package_mac_dmg.sh <path/to/BambuStudio.app> <output.dmg> <volume name>
#
# Environment:
#   SIGN_IDENTITY   codesign identity. Defaults to "-" (ad-hoc). A Developer ID
#                   identity signs the app with the hardened runtime and the
#                   entitlements next to this script, and signs the DMG too.
#   NOTARY_PROFILE  notarytool keychain profile (xcrun notarytool store-credentials).
#                   When set, the app and the DMG are notarized and stapled.
#                   Requires a Developer ID SIGN_IDENTITY.
#   DMG_APP_NAME    bundle name inside the DMG, e.g. "BambuStudio Beta.app", so
#                   dragging it to Applications does not replace an official
#                   install. Defaults to the built bundle's name. Renaming the
#                   bundle folder does not affect its signature.
#
# lipo-merged universal builds carry no valid bundle signature, and macOS reports
# such a downloaded app as "damaged". An ad-hoc signature at least lets users open
# it via System Settings > Privacy & Security; only a notarized Developer ID build
# opens without a warning.

set -euo pipefail

app="$1"
dmg="$2"
volname="$3"
identity="${SIGN_IDENTITY:--}"
notary_profile="${NOTARY_PROFILE:-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$app" ]; then
    echo "App bundle not found: $app" >&2
    exit 1
fi
if [ -n "$notary_profile" ] && [ "$identity" = "-" ]; then
    echo "NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY" >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Submit a file for notarization and fail unless Apple accepts it.
notarize() {
    local file="$1" out status id
    out="$(xcrun notarytool submit "$file" --keychain-profile "$notary_profile" --wait --output-format json)" || true
    echo "$out"
    status="$(plutil -extract status raw -o - - <<<"$out" 2>/dev/null)" || true
    if [ "$status" != "Accepted" ]; then
        id="$(plutil -extract id raw -o - - <<<"$out" || true)"
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$notary_profile" || true
        echo "Notarization of $file failed: $status" >&2
        exit 1
    fi
}

# Extended attributes (e.g. quarantine or Finder info) make codesign fail.
xattr -cr "$app"
if [ "$identity" = "-" ]; then
    codesign --force --deep --sign - "$app"
else
    codesign --force --options runtime --timestamp \
        --entitlements "$script_dir/BambuStudio.entitlements" \
        --sign "$identity" "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
lipo -archs "$app/Contents/MacOS/BambuStudio"

if [ -n "$notary_profile" ]; then
    ditto -c -k --keepParent "$app" "$work/app.zip"
    notarize "$work/app.zip"
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi

staging="$work/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/${DMG_APP_NAME:-$(basename "$app")}"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
# hdiutil intermittently fails with "Resource busy" on CI runners; retry.
for attempt in 1 2 3; do
    if hdiutil create -volname "$volname" -srcfolder "$staging" -ov -format UDZO "$dmg"; then
        break
    fi
    if [ "$attempt" = 3 ]; then
        echo "hdiutil create failed" >&2
        exit 1
    fi
    sleep 10
done
hdiutil verify "$dmg"

if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    codesign --verify --verbose=2 "$dmg"
fi
if [ -n "$notary_profile" ]; then
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

ls -lh "$dmg"
