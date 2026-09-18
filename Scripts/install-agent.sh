#!/usr/bin/env bash
set -euo pipefail

LABEL="local.wokymon"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer an installed copy in /Applications or ~/Applications; fall back to the local build.
APP_BIN="$ROOT_DIR/build/WokyMon.app/Contents/MacOS/WokyMon"
for cand in "/Applications/WokyMon.app/Contents/MacOS/WokyMon" "$HOME/Applications/WokyMon.app/Contents/MacOS/WokyMon"; do
    if [ -x "$cand" ]; then APP_BIN="$cand"; break; fi
done
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/WokyMon"

UNINSTALL=false
if [[ "${1:-}" == "--uninstall" ]]; then
    UNINSTALL=true
fi

if [ "$UNINSTALL" = true ]; then
    echo "==> launchctl bootout gui/$UID ${LABEL}"
    launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Uninstalled $LABEL"
    exit 0
fi

if [ ! -x "$APP_BIN" ]; then
    echo "error: $APP_BIN not found. Run Scripts/make-app.sh first." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$PLIST_PATH")"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${APP_BIN}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ThrottleInterval</key>
	<integer>10</integer>
	<key>StandardOutPath</key>
	<string>${LOG_DIR}/stdout.log</string>
	<key>StandardErrorPath</key>
	<string>${LOG_DIR}/stderr.log</string>
</dict>
</plist>
PLIST

if launchctl print "gui/$UID/${LABEL}" >/dev/null 2>&1; then
    echo "==> already loaded, bootout first"
    launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
fi

echo "==> launchctl bootstrap gui/$UID ${LABEL}"
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
echo "Installed and bootstrapped $LABEL"
echo "Logs: $LOG_DIR"
