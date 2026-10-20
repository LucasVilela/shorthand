#!/bin/bash
# Builds build/Shorthand.app from the Swift package.
#
# The binary is universal (Apple silicon and Intel).
#
# Signing: macOS remembers the Accessibility permission per code signature.
# Uses a "Developer ID Application" identity if there is one (needed to notarize),
# else "Apple Development"; with either, the permission survives rebuilds. With
# ad-hoc signing you have to re-enable Shorthand in Accessibility after each build.
# Override the identity with SIGN_IDENTITY="..." ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64

APP=build/Shorthand.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/apple/Products/Release/Shorthand "$APP/Contents/MacOS/Shorthand"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: every size macOS wants, made from the 1024px logo.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/Logo/shorthand-logo.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/Logo/shorthand-logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

find_identity() {
    security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v kind="$1" '$2 ~ "^"kind { print $2; exit }'
}
IDENTITY="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
IDENTITY="${IDENTITY:-$(find_identity "Apple Development")}"
if [ -n "$IDENTITY" ]; then
    # Hardened runtime and a secure timestamp are what notarization requires.
    TIMESTAMP=--timestamp=none
    [[ "$IDENTITY" == "Developer ID Application"* ]] && TIMESTAMP=--timestamp
    codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed: re-enable Shorthand in Accessibility after each rebuild."
fi

echo "Built $APP"
