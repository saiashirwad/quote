#!/usr/bin/env bash
set -euo pipefail

UID="$(id -u)"
PLIST="${HOME}/Library/LaunchAgents/com.texoport.quote.plist"
BIN="${HOME}/.local/bin/quote"

launchctl bootout "gui/${UID}/com.texoport.quote" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$BIN"
echo "Removed quote launch agent and binary (notes file unchanged)"
