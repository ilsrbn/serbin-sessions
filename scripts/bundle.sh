#!/bin/bash
# Builds a release ClaudeIsland.app (ad-hoc signed) containing the panel and notch-hook.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/ClaudeIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeIsland .build/release/notch-hook "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ilsrbn.claude-island</string>
  <key>CFBundleName</key><string>Claude Island</string>
  <key>CFBundleExecutable</key><string>ClaudeIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP  (hooks binary: $APP/Contents/MacOS/notch-hook)"
