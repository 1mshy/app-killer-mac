#!/bin/bash
# Sourced by build/test scripts; use a functioning local Apple toolchain.
set -euo pipefail
KILLER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KILLER_ROOT"
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ "${CI:-}" != "true" ] && [ -x /Library/Developer/CommandLineTools/usr/bin/swift ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
export CLANG_MODULE_CACHE_PATH="$KILLER_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$KILLER_ROOT/.build/swift-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$KILLER_ROOT/.build/package-cache"
# The bundled 27 SDK requires a SwiftUI macro plugin absent from CLT. The 26.5
# SDK contains all APIs this macOS 26+ utility uses and builds with stock CLT.
if [ -z "${KILLER_SDK:-}" ]; then
  if [ "$DEVELOPER_DIR" = /Library/Developer/CommandLineTools ] && \
     [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    KILLER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  else
    KILLER_SDK="$(xcrun --sdk macosx --show-sdk-path)"
  fi
fi
if [ ! -d "$KILLER_SDK" ]; then
  echo "The configured macOS SDK does not exist: $KILLER_SDK" >&2
  exit 1
fi
export KILLER_SDK
