#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
FIXTURE="$KILLER_ROOT/build/Killer Test App.app"
mkdir -p "$FIXTURE/Contents/MacOS"
swiftc -parse-as-library -swift-version 6 -sdk "$KILLER_SDK" -target "$(uname -m)-apple-macos26.0" Tests/Fixtures/StubbornApp.swift -o "$FIXTURE/Contents/MacOS/KillerTestApp"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.killer.test-app</string>
<key>CFBundleName</key><string>Killer Test App</string>
<key>CFBundleExecutable</key><string>KillerTestApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$FIXTURE"
printf 'Built disposable fixture: %s\n' "$FIXTURE"
