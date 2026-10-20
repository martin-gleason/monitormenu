# Local conventions — MonitorMenu

Created: 2026-10-19 17:34 -05:00 · Edited: 2026-10-19 17:34 -05:00

## Stack

Swift 5.9 language mode, SwiftPM, AppKit, IOKit, macOS 14+, Apple silicon. No lint configured yet. Layout is named in `docs/specs/SPEC.md` § Stack and lands in C1-T1.

## Harness

Declared by `C1`. Until `C1` closes, `check_harness.py` reports this project as undeclared, which is correct.

- run: `swift test`
- count: `scripts/count_assertions.sh`
- floor: `Tests/ASSERTION_FLOOR`
- mutate: `scripts/mutate.sh <M-id>` (applies the named break, runs the catching test, restores)
- precommit: `.githooks/pre-commit`

## Live check

`MONITORMENU_LIVE=1 swift test` runs the tests that talk to the Dell G3223D over DDC. Required after any change to the transport. The app bundle is built with `scripts/build-app.sh` (add `--install` for `~/Applications`).
