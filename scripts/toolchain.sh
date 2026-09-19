#!/bin/bash
# Sourced by build/test scripts; use a functioning local Apple toolchain.
set -euo pipefail
KILLER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KILLER_ROOT"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -x /Library/Developer/CommandLineTools/usr/bin/swift ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export CLANG_MODULE_CACHE_PATH="$KILLER_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$KILLER_ROOT/.build/swift-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$KILLER_ROOT/.build/package-cache"
# The bundled 27 SDK requires a SwiftUI macro plugin absent from CLT. The 26.5
# SDK contains all APIs this macOS 26+ utility uses and builds with stock CLT.
KILLER_SDK="${KILLER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$KILLER_SDK" ]; then KILLER_SDK="$(xcrun --show-sdk-path)"; fi
export KILLER_SDK
