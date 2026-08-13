#!/usr/bin/env bash
# Assemble a SwiftPM executable into a signed .app bundle in ~/Applications.
# Usage: scripts/build-app.sh <product> <bundle-id> <AppName>
set -euo pipefail

PRODUCT="$1"; BUNDLE_ID="$2"; APP_NAME="$3"
CONFIG="${CONFIG:-debug}"
: "${KUTU_SIGN_IDENTITY:?set KUTU_SIGN_IDENTITY (e.g. 'Apple Development: Your Name (TEAMID)')}"

swift build -c "$CONFIG" --product "$PRODUCT" >&2
BIN_DIR="$(swift build -c "$CONFIG" --product "$PRODUCT" --show-bin-path)"

APP="$HOME/Applications/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
codesign --force --sign "$KUTU_SIGN_IDENTITY" "$APP" >&2
echo "$APP"
