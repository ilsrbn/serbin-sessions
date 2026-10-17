#!/bin/bash
# Builds a release SerbinSessions.app (ad-hoc signed) containing the panel and notch-hook.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/SerbinSessions.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SerbinSessions .build/release/notch-hook "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources" && cp assets/brand/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ilsrbn.serbin-sessions</string>
  <key>CFBundleName</key><string>Serbin Sessions</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>SerbinSessions</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>dev.ilsrbn.serbin-sessions</string>
    <key>CFBundleURLSchemes</key><array><string>serbin-sessions</string><string>claude-island</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP  (hooks binary: $APP/Contents/MacOS/notch-hook)"

# Hooks in ~/.claude/settings.json point at /Applications, so always install the fresh build there
# and relaunch it (skip with NO_INSTALL=1).
if [ -z "${NO_INSTALL:-}" ]; then
  DEST="/Applications/Serbin Sessions.app"
  killall SerbinSessions 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
