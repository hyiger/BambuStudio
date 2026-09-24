#!/bin/bash
# Package a built BambuStudio.app into a compressed, drag-to-install DMG.
#
# Usage: package_mac_dmg.sh <path/to/BambuStudio.app> <output.dmg> <volume name>
#
# The app is ad-hoc signed first. lipo-merged universal builds carry no valid
# bundle signature, and macOS reports such a downloaded app as "damaged"; an
# ad-hoc signature lets users open it via System Settings > Privacy & Security
# instead. This is not a Developer ID signature and the app is not notarized.

set -euo pipefail

app="$1"
dmg="$2"
volname="$3"

if [ ! -d "$app" ]; then
    echo "App bundle not found: $app" >&2
    exit 1
fi

# Extended attributes (e.g. quarantine or Finder info) make codesign fail.
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -archs "$app/Contents/MacOS/BambuStudio"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/$(basename "$app")"
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
ls -lh "$dmg"
