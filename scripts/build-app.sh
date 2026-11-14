#!/bin/bash
# Builds ViFinder.app into ./build
#
#   scripts/build-app.sh [debug|release] [native|universal]
#
#   native     - current Mac's architecture only (fast, default)
#   universal  - arm64 + x86_64 merged with lipo (Apple Silicon + Intel)
#
# Optional: VERSION=1.2.0 sets CFBundleShortVersionString, BUILD_NUMBER sets CFBundleVersion.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
MODE="${2:-native}"
APP="build/ViFinder.app"
BIN="$APP/Contents/MacOS/ViFinder"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$MODE" = "universal" ]; then
  for ARCH in arm64 x86_64; do
    echo "==> Compiling $ARCH ($CONFIG)..."
    swift build -c "$CONFIG" --arch "$ARCH"
  done
  echo "==> Merging into a universal binary..."
  lipo -create \
    "$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/ViFinder" \
    "$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/ViFinder" \
    -output "$BIN"
else
  echo "==> Compiling ($CONFIG)..."
  swift build -c "$CONFIG"
  cp "$(swift build -c "$CONFIG" --show-bin-path)/ViFinder" "$BIN"
fi

echo "==> Assembling ${APP}..."
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [ ! -f Support/AppIcon.icns ]; then
  echo "==> Generating icon..."
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Support/AppIcon.icns
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP" >/dev/null

echo "OK: Built $APP ($(lipo -archs "$BIN"))"
