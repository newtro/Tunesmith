#!/bin/zsh
# Rebuilds and reinstalls Tunesmith.app when any source file has changed since the
# last successful build. Run on a timer by com.scott.tunesmith.autobuild.
set -uo pipefail
cd "$(dirname "$0")/.."

STAMP=".build/.autobuild-stamp"
LOG="$HOME/Library/Logs/tunesmith-autobuild.log"

# Newest mtime across everything that affects the app bundle.
NEWEST=$(find Sources Package.swift Info.plist make-icon.swift build.sh -type f -newer "$STAMP" 2>/dev/null | head -1)
[[ -f "$STAMP" && -z "$NEWEST" ]] && exit 0

echo "--- $(date '+%F %T') rebuild (trigger: ${NEWEST:-first run})" >>"$LOG"
if ./build.sh >>"$LOG" 2>&1; then
  mkdir -p .build && touch "$STAMP"
  echo "    ok" >>"$LOG"
else
  echo "    FAILED — leaving the installed app alone until it builds" >>"$LOG"
fi
