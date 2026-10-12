#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh android

# Fixed signing key (GitHub secret) => every build has the same signature, so updates install over the old app.
if [ -n "${DEBUG_KEYSTORE_BASE64:-}" ]; then
  mkdir -p "$HOME/.android"
  echo "$DEBUG_KEYSTORE_BASE64" | base64 -d > "$HOME/.android/debug.keystore"
  cp "$HOME/.android/debug.keystore" android/app/ramtv.keystore
  python3 ci/sign.py
  echo "Using fixed signing key"
fi

set +e
flutter build apk --release --split-per-abi --dart-define=TMDB_KEY="${TMDB_KEY:-}" 2>&1 | tee build.log
st=${PIPESTATUS[0]}
set -e
if [ "$st" -ne 0 ]; then bash ci/report_errors.sh build.log; exit "$st"; fi

mkdir -p ../dist
OUT=build/app/outputs/flutter-apk
cp "$OUT/app-arm64-v8a-release.apk" ../dist/RaM-tv-Android-arm64.apk
cp "$OUT/app-armeabi-v7a-release.apk" ../dist/RaM-tv-Android-arm32.apk
cp "$OUT/app-arm64-v8a-release.apk" ../dist/RaM-tv-Android-TV-arm64.apk
cp "$OUT/app-armeabi-v7a-release.apk" ../dist/RaM-tv-Android-TV-arm32.apk
ls -la ../dist

# Report the signing certificate fingerprint (proves updates will install over previous builds)
APKSIGNER=$(ls "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)
for f in ../dist/*.apk; do
  FP=""
  if [ -n "$APKSIGNER" ]; then FP=$("$APKSIGNER" verify --print-certs "$f" 2>/dev/null | grep -m1 "SHA-256" || true); fi
  echo "::notice title=APK signature::$(basename "$f") ${FP:-unknown}"
done
