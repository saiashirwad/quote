#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG="$ROOT/.build/dev.log"
: > "$LOG"

"$ROOT/scripts/bundle.sh"
pkill -x quote || true

open -n --stdout "$LOG" --stderr "$LOG" "$ROOT/.build/Quote.app"

trap 'pkill -x quote' INT TERM EXIT
tail -f "$LOG"
