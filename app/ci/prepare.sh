#!/bin/bash
# Usage: prepare.sh <android|windows|macos>   (run from anywhere)
set -euo pipefail
cd "$(dirname "$0")/.."

PY=$(command -v python3 || command -v python)

flutter --version
rm -rf _scaffold
flutter create --platforms=android,windows,macos --org com.ramzi --project-name ramtv _scaffold
for d in android windows macos; do
  rm -rf "$d"
  cp -R "_scaffold/$d" "$d"
done
rm -rf _scaffold

flutter pub get
dart run flutter_launcher_icons
"$PY" ci/patch.py "$1"
