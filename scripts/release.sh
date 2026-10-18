#!/bin/bash
# Free release (no Apple Developer ID): ad-hoc signed DMG -> GitHub Release -> cask in our Homebrew tap.
#   ./scripts/release.sh                 build build/SerbinSessions-<version>.dmg and packaging/homebrew/serbin-sessions.rb
#   PUBLISH=1 ./scripts/release.sh       also create the GitHub Release (needs `gh auth login`)
#   TAP_DIR=../homebrew-tap PUBLISH=1 …  also copy the cask into a local clone of the tap, commit and push
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${REPO:-ilsrbn/serbin-sessions}

NO_INSTALL=1 ./scripts/bundle.sh
APP=build/SerbinSessions.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
TAG="v$VERSION"

# Disk image with the app named as it is installed, plus an /Applications shortcut.
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Serbin Sessions.app"
ln -s /Applications "$STAGE/Applications"
DMG="build/SerbinSessions-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Serbin Sessions" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

CASK=packaging/homebrew/serbin-sessions.rb
sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    -e "s#github.com/[^/\"]*/[^/\"]*#github.com/$REPO#g" "$CASK" > "$CASK.tmp" && mv "$CASK.tmp" "$CASK"
echo "Built $DMG ($SHA), updated $CASK"

[ -n "${PUBLISH:-}" ] || exit 0

# Release notes = this version's section of CHANGELOG.md.
NOTES=$(awk -v v="$VERSION" '$0 ~ "^## "v {f=1; next} /^## / {f=0} f' CHANGELOG.md)
gh release create "$TAG" "$DMG" --repo "$REPO" --title "Serbin Sessions $VERSION" --notes "$NOTES"

if [ -n "${TAP_DIR:-}" ]; then
  mkdir -p "$TAP_DIR/Casks"
  cp "$CASK" "$TAP_DIR/Casks/"
  git -C "$TAP_DIR" add Casks/serbin-sessions.rb
  git -C "$TAP_DIR" commit -m "serbin-sessions $VERSION"
  git -C "$TAP_DIR" push
fi
