#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh windows
flutter build windows --release --dart-define=TMDB_KEY="${TMDB_KEY:-}"
mkdir -p ../dist
REL=$(find build/windows -type d -name Release | head -1)
echo "Release folder: $REL"
powershell -NoProfile -Command "Compress-Archive -Path '$REL/*' -DestinationPath '../dist/RaM-tv-Windows-x64.zip' -Force"
ls -la ../dist
