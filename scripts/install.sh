#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

BIN_DST="${HOME}/.local/bin/quote"
mkdir -p "${HOME}/.local/bin"
cp "$ROOT/.build/release/quote" "$BIN_DST"
chmod +x "$BIN_DST"
codesign --force --sign - "$BIN_DST"

rm -rf "${HOME}/Applications/Quote.app"

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
    <string>${BIN_DST}</string>
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
echo "Installed quote → $BIN_DST (launchd com.texoport.quote)"
