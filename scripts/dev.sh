#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/bundle.sh"
pkill -x quote || true
exec "$ROOT/.build/Quote.app/Contents/MacOS/quote"
