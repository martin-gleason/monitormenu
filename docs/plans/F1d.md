# F1d — PiP modes by name, one entry per layout

Created: 2026-10-29 12:11 -05:00 · Edited: 2026-10-29 12:15 -05:00

**Status:** built 2026-10-29, evidence gathered, review pending; no gate (closes `O5` and `RR5` under FR4; the one user-visible choice, hiding ignored and duplicate values, is `D21`, ratified by the owner at the desk: "so for v1.0, let's hide that. and open it up as a more customizable option in v1.5") · **Milestone:** v1.0 (patch 1.0.1) · **Owner:** agent · **Retrofits:** F1 (FR4)

Learning level 5%, locked (`O2`); every task is `owner: agent`.

## What the user gets

The PiP submenu and `monitorctl list` stop showing six raw hex values. On the G3223D the list reads Off · PiP small · PiP large · PbP 50/50 · PbP 25/75 · PbP 75/25, each a different picture on screen. `monitorctl set pip 25/75` and `75/25` work as words. The four values the mapping session found to be no-ops or duplicates (`docs/learnings/2026-10-29-pip-values.md`) are not offered; `set pip 0x2D` still goes through, because the monitor advertises it (NFR5 is about what the monitor offers, D21 is about what the menu offers).

## Why no gate

The labels close `O5`, open since 2026-10-19 under FR4. Hiding values is a product choice and has its decision (`D21`). The v1.5 half, a customizable PiP list, is `D22`, proposed, and nothing here builds it.

## Tasks

### F1d-T1 — Labels, hidden values, words (MonitorCore)
Owner: agent · `VCP.vendorLabels[pipMode]` gains 0x29, 0x2A, 0x2D, 0x2E from the mapping; `VCP.hiddenPiPValues` per vendor lists 0x01, 0x02 (ignored by the firmware) and 0x2D, 0x2E (duplicates) with the reason beside each; `VCP.pipCode(from:)` accepts `25/75`, `75/25` (and `25-75`, `75-25`). `Monitor.pipModes()` returns the advertised values minus the hidden ones; `Monitor.setPiPMode` is unchanged. Checkpoint: `VCPTests` label and word tests; `WhitelistTests` shows `pipModes()` drops the four and `setPiPMode(0x2D)` still writes.

### F1d-T2 — The surfaces follow
Owner: agent · The menu's PiP submenu and `monitorctl list` (text and JSON) already iterate `pipModes()`, so they follow T1; this task is the live check, not new code. Checkpoint: `monitorctl list` prints six modes; the installed app's submenu shows six; `monitorctl set pip 0x2D` is accepted and `get pip` names it.

### F1d-T3 — Mutation, floor, version
Owner: agent · `M14`: ignore the hidden set in `pipModes()`, caught by the T1 whitelist test. `Tests/ASSERTION_FLOOR` raised to the new count. `MonitorCore.version` 1.0.1. Checkpoint: `scripts/mutate.sh M14` red; floor met.

### F1d-T4 — Adversarial review
Owner: agent · `docs/reviews/F1d.md`. Checkpoint: findings fixed or on the record.

## Evidence (2026-10-29, before the review)

| Check | Result | How |
|---|---|---|
| suite and floor | `Executed 43 tests, with 1 test skipped and 0 failures`; floor 43 | `swift test` |
| M14 killed | 1 failure / 1 test | `scripts/mutate.sh M14` |
| six modes listed | text: `Off (0x00) PiP small (0x21) PiP large (0x22) PbP 50/50 (0x24) PbP 25/75 (0x29) PbP 75/25 (0x2A)`; JSON `pipModes` names the same six | `.build/debug/monitorctl list`, `list --json` |
| hidden value still settable | `set pip 0x2D` → `pip → PbP 25/75`; `get pip` → `PbP 25/75 (0x2D)` | owner at the desk, one retrain |
| ratio word | `set pip 25/75` → `PbP 25/75 (0x29)`; then `off` → `Off (0x00)` | same |
| menu submenu shows six | not yet checked in the installed app: needs the 1.0.1 build installed (after the review) | — |
| mapping on record | `docs/learnings/2026-10-29-pip-values.md` | — |

## Risks touched

RR5 closes. RR9 (retrains) unchanged. New, small: another Dell with the same vendor id may give 0x2D a distinct meaning; the hidden set is keyed by vendor today and `D22` moves it to the user's control.
