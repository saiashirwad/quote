#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG="$ROOT/.build/dev.log"
: > "$LOG"

"$ROOT/scripts/bundle.sh"
pkill -x quote || true

open -n "$ROOT/.build/Quote.app" --stdout "$LOG" --stderr "$LOG"

trap 'pkill -x quote' INT TERM EXIT
tail -f "$LOG"
