#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/bundle.sh" >/dev/null

APP_DST="${HOME}/Applications/Quote.app"
EXE="${APP_DST}/Contents/MacOS/quote"
mkdir -p "${HOME}/Applications"
rm -rf "$APP_DST"
ditto "$ROOT/.build/Quote.app" "$APP_DST"

rm -f "${HOME}/.local/bin/quote"

LOG_DIR="${HOME}/Library/Logs"
PLIST="${HOME}/Library/LaunchAgents/com.texoport.quote.plist"
mkdir -p "${HOME}/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.texoport.quote</string>
  <key>ProgramArguments</key>
  <array>
    <string>${EXE}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/quote.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/quote.log</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/${UID}/com.texoport.quote" 2>/dev/null || true
launchctl bootstrap "gui/${UID}" "$PLIST"
echo "Installed Quote.app → $APP_DST (launchd com.texoport.quote)"
