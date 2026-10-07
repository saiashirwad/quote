#!/usr/bin/env bash
set -euo pipefail

PLIST="${HOME}/Library/LaunchAgents/com.texoport.quote.plist"
APP="${HOME}/Applications/Quote.app"
LEGACY_BIN="${HOME}/.local/bin/quote"

launchctl bootout "gui/${UID}/com.texoport.quote" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP"
rm -f "$LEGACY_BIN"
echo "Removed quote launch agent and app (notes file unchanged)"
