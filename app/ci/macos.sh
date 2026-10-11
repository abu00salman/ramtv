#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh macos
flutter build macos --release
mkdir -p ../dist
APP=$(find build/macos/Build/Products/Release -maxdepth 1 -name "*.app" | head -1)
echo "App bundle: $APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" ../dist/RaM-tv-macOS.zip
ls -la ../dist
