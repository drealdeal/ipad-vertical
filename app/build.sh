#!/bin/bash
# Builds "iPad Vertical.app" into the project folder. Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="../iPad Vertical.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -import-objc-header Bridge.h main.swift \
  -framework AppKit -framework ScreenCaptureKit -framework Carbon \
  -o "$APP/Contents/MacOS/iPadVertical"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.doruk.ipadvertical</string>
  <key>CFBundleName</key><string>iPad Vertical</string>
  <key>CFBundleExecutable</key><string>iPadVertical</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built: $APP"
