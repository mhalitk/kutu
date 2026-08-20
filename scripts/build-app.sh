#!/usr/bin/env bash
# Assemble a SwiftPM executable into a signed .app bundle in ~/Applications.
# Usage: scripts/build-app.sh <product> <bundle-id> <AppName>
set -euo pipefail

PRODUCT="$1"; BUNDLE_ID="$2"; APP_NAME="$3"
CONFIG="${CONFIG:-debug}"
# Ad-hoc by default, so a clone builds with no Apple account of any kind. That
# is enough to run the app, but macOS identifies an ad-hoc signature by its
# hash: every rebuild looks like a different app and Accessibility has to be
# granted again. Setting KUTU_SIGN_IDENTITY to a real certificate ties the
# signature to your team and bundle id instead, and the grant survives rebuilds.
SIGN_IDENTITY="${KUTU_SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "build-app.sh: signing ad-hoc; expect to re-grant Accessibility after each rebuild." >&2
    echo "              set KUTU_SIGN_IDENTITY to a certificate to avoid that (see README)." >&2
fi

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
<key>CFBundleIconFile</key><string>$APP_NAME</string>
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

# Rendered from KutuMark rather than copied from a committed .icns, so the icon
# cannot fall out of step with the mark the app draws in its own UI.
swift build -c "$CONFIG" --product kutu-icon >&2
ICON_BIN="$(swift build -c "$CONFIG" --product kutu-icon --show-bin-path)"
mkdir -p "$APP/Contents/Resources"
"$ICON_BIN/kutu-icon" "$APP/Contents/Resources/$APP_NAME.icns" >&2

codesign --force --sign "$SIGN_IDENTITY" "$APP" >&2
echo "$APP"
