#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh macos

set +e
flutter build macos --release --dart-define=TMDB_KEY="${TMDB_KEY:-}" 2>&1 | tee build.log
st=${PIPESTATUS[0]}
set -e
if [ "$st" -ne 0 ]; then bash ci/report_errors.sh build.log; exit "$st"; fi

mkdir -p ../dist
APP=$(find build/macos/Build/Products/Release -maxdepth 1 -name "*.app" | head -1)
echo "App bundle: $APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" ../dist/RaM-tv-macOS.zip
ls -la ../dist
