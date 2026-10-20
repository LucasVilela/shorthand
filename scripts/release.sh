#!/bin/bash
# Builds a release of Shorthand: tests, app, signature check, zip and SHA-256 in build/.
# Notarizes when NOTARY_PROFILE names a `notarytool store-credentials` profile and the
# app is signed with a Developer ID certificate.
#
#   ./scripts/release.sh             build the zip only
#   ./scripts/release.sh --publish   also tag v<version>, push the tag and create the
#                                    GitHub release, with the CHANGELOG section as notes
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
PUBLISH=false
[ "${1:-}" = "--publish" ] && PUBLISH=true

NOTES=$(awk -v heading="## $VERSION " 'index($0, heading) == 1 { on = 1; next } /^## / && on { exit } on' CHANGELOG.md)
if [ -z "$(echo "$NOTES" | tr -d '[:space:]')" ]; then
    echo "CHANGELOG.md has no '## $VERSION — <date>' section." >&2
    exit 1
fi

if $PUBLISH; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "Commit or stash your changes first." >&2
        exit 1
    fi
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        echo "Tag $TAG already exists. Bump the version in Resources/Info.plist." >&2
        exit 1
    fi
fi

swift test
./scripts/build-app.sh

APP=build/Shorthand.app
ZIP_NAME="Shorthand-$VERSION.zip"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Shorthand"

make_zip() {
    rm -f "build/$ZIP_NAME"
    ditto -c -k --keepParent "$APP" "build/$ZIP_NAME"
}
make_zip

if [ -n "${NOTARY_PROFILE:-}" ]; then
    if ! codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
        echo "Notarizing needs a Developer ID Application certificate (see README)." >&2
        exit 1
    fi
    xcrun notarytool submit "build/$ZIP_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    make_zip
    spctl --assess --type execute --verbose "$APP"
else
    echo "Not notarized: macOS on other Macs will ask before opening it (see README)."
fi

(cd build && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256" && cat "$ZIP_NAME.sha256")

if $PUBLISH; then
    git tag -a "$TAG" -m "Shorthand $VERSION"
    git push origin "$TAG"
    gh release create "$TAG" "build/$ZIP_NAME" "build/$ZIP_NAME.sha256" \
        --title "Shorthand $VERSION" --notes "$NOTES" --verify-tag
fi
