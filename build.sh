#!/bin/zsh
# Builds Tunesmith.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release 2>&1 | grep -v "^\[" | tail -5

APP="dist/Tunesmith.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tunesmith "$APP/Contents/MacOS/Tunesmith"
cp Info.plist "$APP/Contents/Info.plist"

if swift make-icon.swift >/dev/null 2>&1 && iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "icon: ok"
else
  echo "icon: skipped"
fi
rm -rf dist/AppIcon.iconset

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "codesign: ad-hoc ok"

mkdir -p ~/Applications
rm -rf ~/Applications/Tunesmith.app
cp -R "$APP" ~/Applications/
echo "installed: ~/Applications/Tunesmith.app"
