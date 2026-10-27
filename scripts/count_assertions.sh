#!/bin/zsh
# Created: 2026-10-19 19:22 -05:00 · Edited: 2026-10-27 09:26 -05:00
# C1-T2: prints one integer — the number of tests `swift test` actually executed.
# An exit code cannot show a suite that stopped running; this count can.
set -uo pipefail
cd "$(dirname "$0")/.."
out=$(swift test 2>&1)
n=$(printf '%s\n' "$out" | grep -E "Executed [0-9]+ tests?" | tail -1 | sed -E 's/.*Executed ([0-9]+) tests?.*/\1/')
echo "${n:-0}"
