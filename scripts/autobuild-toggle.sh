#!/bin/zsh
# Turns the Tunesmith auto-rebuild agent on or off:  scripts/autobuild-toggle.sh on|off|status
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
LABEL="com.scott.tunesmith.autobuild"
TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"

case "${1:-status}" in
  on)
    sed -e "s|__REPO__|$REPO|g" -e "s|__HOME__|$HOME|g" scripts/$LABEL.plist >"$TARGET"
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$TARGET"
    echo "on — rebuilds within ~15s of a save; log: ~/Library/Logs/tunesmith-autobuild.log"
    ;;
  off)
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    rm -f "$TARGET"
    echo "off"
    ;;
  status)
    launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 && echo "on" || echo "off"
    ;;
  *) echo "usage: $0 on|off|status" >&2; exit 2 ;;
esac
