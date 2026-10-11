#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh android
flutter build apk --release --split-per-abi
mkdir -p ../dist
OUT=build/app/outputs/flutter-apk
cp "$OUT/app-arm64-v8a-release.apk" ../dist/RaM-tv-Android-arm64.apk
cp "$OUT/app-armeabi-v7a-release.apk" ../dist/RaM-tv-Android-arm32.apk
ls -la ../dist
