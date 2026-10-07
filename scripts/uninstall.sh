#!/usr/bin/env bash
set -euo pipefail

PLIST="${HOME}/Library/LaunchAgents/com.texoport.quote.plist"
BIN="${HOME}/.local/bin/quote"
APP="${HOME}/Applications/Quote.app"

launchctl bootout "gui/${UID}/com.texoport.quote" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$BIN"
rm -rf "$APP"
echo "Removed quote launch agent and binary (notes file unchanged)"
