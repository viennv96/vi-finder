#!/bin/bash
# Packages build/ViFinder.app into build/ViFinder.dmg and build/ViFinder.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ViFinder.app"
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first"; exit 1; }

echo "==> Creating build/ViFinder.zip..."
rm -f build/ViFinder.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" build/ViFinder.zip

echo "==> Creating build/ViFinder.dmg..."
STAGE="build/dmg"
rm -rf "$STAGE" build/ViFinder.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname ViFinder -srcfolder "$STAGE" -ov -format UDZO build/ViFinder.dmg >/dev/null
rm -rf "$STAGE"

echo "OK: build/ViFinder.dmg, build/ViFinder.zip"
