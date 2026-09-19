#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
KILLER_APP="$KILLER_ROOT/build/Killer.app"
KILLER_ARCH="$(uname -m)"
case "$KILLER_ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $KILLER_ARCH" >&2; exit 1 ;;
esac

# Verify the actual bundle, including its helper, before archiving it.
test -x "$KILLER_APP/Contents/MacOS/Killer"
test -x "$KILLER_APP/Contents/Helpers/KillerPrivileged"
/usr/bin/codesign --verify --deep --strict "$KILLER_APP"
/usr/bin/plutil -lint "$KILLER_APP/Contents/Info.plist"
# Xcode 26's lipo consumes every argument after -verify_arch as an architecture.
/usr/bin/lipo "$KILLER_APP/Contents/MacOS/Killer" -verify_arch "$KILLER_ARCH"
/usr/bin/lipo "$KILLER_APP/Contents/Helpers/KillerPrivileged" -verify_arch "$KILLER_ARCH"

mkdir -p build/artifacts
KILLER_ARCHIVE="Killer-macOS-$KILLER_ARCH.zip"
/usr/bin/ditto -c -k --keepParent "$KILLER_APP" "build/artifacts/$KILLER_ARCHIVE"

# A GitHub artifact must preserve executable bits and bundle signatures after
# extraction. Validate that property rather than uploading a raw .app directory.
KILLER_UNPACK="$(mktemp -d "${TMPDIR:-/tmp}/killer-package.XXXXXX")"
trap 'rm -rf "$KILLER_UNPACK"' EXIT
/usr/bin/ditto -x -k "build/artifacts/$KILLER_ARCHIVE" "$KILLER_UNPACK"
test -x "$KILLER_UNPACK/Killer.app/Contents/MacOS/Killer"
test -x "$KILLER_UNPACK/Killer.app/Contents/Helpers/KillerPrivileged"
/usr/bin/codesign --verify --deep --strict "$KILLER_UNPACK/Killer.app"

cd build/artifacts
/usr/bin/shasum -a 256 "$KILLER_ARCHIVE" > "$KILLER_ARCHIVE.sha256"
/usr/bin/shasum -a 256 -c "$KILLER_ARCHIVE.sha256"
printf 'Packaged %s/build/artifacts/%s\n' "$KILLER_ROOT" "$KILLER_ARCHIVE"
