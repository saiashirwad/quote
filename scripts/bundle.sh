#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/.build/Quote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$ROOT/.build/release/quote" "$APP/Contents/MacOS/quote"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
	IDENTITY="$(
		security find-identity -v -p codesigning 2>/dev/null \
			| awk '/Apple Development/ { print $2; exit }'
	)"
fi
if [[ -z "$IDENTITY" ]]; then
	IDENTITY="-"
fi

echo "Signing with identity: $IDENTITY"
codesign --force --sign "$IDENTITY" "$APP"

echo "$APP"
