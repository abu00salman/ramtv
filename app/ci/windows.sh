#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash ci/prepare.sh windows

set +e
flutter build windows --release --dart-define=TMDB_KEY="${TMDB_KEY:-}" 2>&1 | tee build.log
st=${PIPESTATUS[0]}
set -e
if [ "$st" -ne 0 ]; then bash ci/report_errors.sh build.log; exit "$st"; fi

PY=$(command -v python3 || command -v python)
REL=$(find build/windows -type d -name Release | head -1)
echo "Release folder: $REL"
mkdir -p ../dist
"$PY" - "$REL" ../dist/RaM-tv-Windows-x64 <<'PYEOF'
import sys, shutil
shutil.make_archive(sys.argv[2], "zip", sys.argv[1])
PYEOF
test -f ../dist/RaM-tv-Windows-x64.zip || { echo "::error::Windows zip was not created"; exit 1; }
ls -la ../dist
