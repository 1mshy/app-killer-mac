#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
# Explicit registration avoids intermittent SwiftBuild macro discovery failures
# when using a Command Line Tools SDK rather than the full Xcode platform SDK.
KILLER_SWIFTC="$(xcrun --find swiftc)"
KILLER_TEST_MACROS="$(dirname "$(dirname "$KILLER_SWIFTC")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
KILLER_TEST_FLAGS=(--sdk "$KILLER_SDK" --disable-sandbox --cache-path "$KILLER_ROOT/.build/package-cache")
if [ -f "$KILLER_TEST_MACROS" ]; then
  KILLER_TEST_FLAGS+=( -Xswiftc -load-plugin-library -Xswiftc "$KILLER_TEST_MACROS" )
fi
swift test "${KILLER_TEST_FLAGS[@]}" "$@"
