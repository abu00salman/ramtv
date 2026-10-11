#!/bin/bash
# Usage: report_errors.sh <logfile>
# Emits the first error lines as GitHub annotations (readable through the API).
LOG="${1:-build.log}"
[ -f "$LOG" ] || exit 0
grep -E -i "error|failed|what went wrong|exception|could not|cannot" "$LOG" | grep -v -i "0 errors" | head -10 | while IFS= read -r l; do
  l="${l//$'\r'/}"
  echo "::error::${l:0:900}"
done
