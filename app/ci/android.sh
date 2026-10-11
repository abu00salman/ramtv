#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh android

# Fixed signing key (GitHub secret) => every build has the same signature, so updates install over the old app.
if [ -n "${DEBUG_KEYSTORE_BASE64:-}" ]; then
  mkdir -p "$HOME/.android"
  echo "$DEBUG_KEYSTORE_BASE64" | base64 -d > "$HOME/.android/debug.keystore"
  echo "Using fixed signing key"
fi
flutter build apk --release --split-per-abi --dart-define=TMDB_KEY="${TMDB_KEY:-}"
mkdir -p ../dist
OUT=build/app/outputs/flutter-apk
cp "$OUT/app-arm64-v8a-release.apk" ../dist/RaM-tv-Android-arm64.apk
cp "$OUT/app-armeabi-v7a-release.apk" ../dist/RaM-tv-Android-arm32.apk
ls -la ../dist
