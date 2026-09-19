#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Usage: scripts/build.sh [release|debug]" >&2
  exit 64
fi
if [ -n "${KILLER_VERSION:-}" ] && [[ ! "$KILLER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "KILLER_VERSION must use MAJOR.MINOR.PATCH." >&2
  exit 64
fi
if [ -n "${KILLER_BUILD_NUMBER:-}" ] && [[ ! "$KILLER_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "KILLER_BUILD_NUMBER must contain only digits." >&2
  exit 64
fi
swift build -c "$CONFIGURATION" --sdk "$KILLER_SDK" --disable-sandbox --cache-path "$KILLER_ROOT/.build/package-cache"
BIN_DIR="$(swift build -c "$CONFIGURATION" --sdk "$KILLER_SDK" --show-bin-path --disable-sandbox --cache-path "$KILLER_ROOT/.build/package-cache")"
APP="$KILLER_ROOT/build/Killer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN_DIR/Killer" "$APP/Contents/MacOS/Killer"
cp "$BIN_DIR/KillerPrivileged" "$APP/Contents/Helpers/KillerPrivileged"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${KILLER_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $KILLER_VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${KILLER_BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $KILLER_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
cp Resources/Help.html "$APP/Contents/Resources/Help.html"
if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  swift -sdk "$KILLER_SDK" scripts/make-icon.swift "$KILLER_ROOT/build"
  /usr/bin/iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$APP/Contents/Helpers/KillerPrivileged"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
printf '\nBuilt %s\nOpen it with: open "%s"\n' "$APP" "$APP"
