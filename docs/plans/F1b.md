# F1b — Second pass over F1: handle lifecycle and the review's loose ends

Created: 2026-10-23 09:20 -05:00 · Edited: 2026-10-23 09:40 -05:00

**Status:** built 2026-10-23; no gate (defect fixes from the second adversarial pass, `A2`, plus `A1`, whose decision criterion in the register was met by measurement) · **Milestone:** v1.0 · **Owner:** agent · **Retrofits:** F1 (FR2, FR3, FR4, FR8, NFR4, NFR5)

Learning level 5%, locked (`O2`); every task is `owner: agent`.

## What the user gets

Nothing new to click. The action after a PiP or input change stops failing on a dead handle and retrying for seconds; a monitor that hangs cannot take the whole app's I2C layer down with it; `monitorctl set brightness 500` is refused like the menu already refused it; the secret scan and the commit hook close two gaps.

## Why no gate

Everything here traces to a finding in `docs/reviews/F1.md` § Second pass (2026-10-23) or to `A1`, whose register row said "measure first". Measured 2026-10-23: creating the IOKit handle costs 0.5 ms, a fresh handle per read adds about 4 ms to a 62 ms read. The owner can reject the `A1` half in PR review; it is the `IOAVServiceChannel` change and nothing else depends on it.

## Tasks

### F1b-T1 — Per-transaction IOAVService (`A1`, RR9)
Owner: agent · `IOAVServiceChannel` keeps the registry node's id and display key, creates the handle per call, and re-finds the display's service when the node was replaced. Checkpoint: one `Monitor` object held across a PiP change reads brightness afterwards without rediscovery.

### F1b-T2 — Timeout is not retried; one serial I/O queue per channel (review A2-1, A2-2)
Owner: agent · `DDCMonitorLink.attempt` throws on `timeout` at once (M8); `DeadlineChannel` owns a serial queue; `MonitorStore.perform` treats a timeout like a lost handle. Checkpoint: `testTimeoutIsNotRetried`, `testHungChannelDoesNotStarveAnother`.

### F1b-T3 — Continuous codes read their range before the first write (A2-3)
Owner: agent · `Monitor.set` reads the maximum once when unknown (M9); `monitorctl` bounds brightness and contrast to 0–100 as its message says. Checkpoint: `testContinuousWriteReadsTheMaximumFirst`; `monitorctl set brightness 500` → `number 0–100`.

### F1b-T4 — Unsupported-result replies, coalesced discovery, cached capabilities (A2-6, A2-7)
Owner: agent · `parseVCPReply` throws on MCCS result 0x01; `MonitorStore.discover` runs one at a time and reuses capabilities by serial (Rescan re-reads). Checkpoint: `testUnsupportedResultByteIsRejected`; code path.

### F1b-T5 — Hooks (A2-4, A2-5)
Owner: agent · pre-commit catches `*_secret_access_key`, `*_SECRET_KEY` and `sk_live_` / `sk_test_`; commit-msg exempts Apple chip names (`M1 Mac`). Checkpoint: crafted lines below.

## Evidence (2026-10-23)

| Check | Result | How |
|---|---|---|
| suite | `Executed 29 tests, with 1 test skipped and 0 failures`; floor 25 → 29 | `swift test`, `scripts/count_assertions.sh` |
| M8, M9 | see `docs/reviews/F1.md` § Second pass | `scripts/mutate.sh M8`, `M9` |
| A1 cost | lookup+create mean 0.4–0.5 ms; held-handle read mean 61.5 ms; fresh handle+read mean 65 ms; 20/20 reads both ways, two runs | scratch probe `handlecost` (standalone, IOKit only) |
| A1 live | one `Monitor` held across `setPiPMode(0x21)`: 9 s later `brightness()` → 56 in 788 ms, `currentPiPMode()` → 0x21 in 517 ms, registry node id had changed (0x10028ea23 → 0x10028ed37). Across `setPiPMode(0x00)`: at 9 s the monitor answered the brightness read with null messages for 2.1 s (not ready yet), the PiP read right after succeeded (0x00) in 1.4 s. Before this change the first read after either retrain failed with `MACH_SEND_INVALID_DEST`. | scratch probe `retrain` linked against `MonitorCore` |
| live reads through the per-call handle | `monitorctl probe --count 20` → 20/20, mean 130 ms (was 115 ms held: two lookups and two handles per read) | terminal |
| A2-3 | `monitorctl set brightness 500` → `number 0–100`, rc 1 | terminal |
| A2-4 | `aws_secret_access_key = …`, `AWS_SECRET_ACCESS_KEY: "…"`, `STRIPE_SECRET_KEY=sk_live_…` all caught; `let secretSauce = "onions"` passes | hook regex on crafted lines |
| A2-5 | `fix(F1b): tested on an M1 Mac and an M2 Pro` accepted; `closes A3`, `M8 is a mutation`, `M1 Mac and M2 Ultra, M9 though` refused | `.githooks/commit-msg` |
| not reproduced | A2-7 (fewer discoveries per change) is by code reading: every path funnels through `discover()`, which runs one at a time and reuses capabilities; the app's log is not retrievable on this Mac to count them | — |

## Observation, not explained

Between 09:02 and 09:10 on 2026-10-23, with no PiP or input write from this side, both `DCPAVServiceProxy` nodes (Embedded and External) were recreated with new registry ids and for about two minutes neither `monitorctl` nor a standalone probe could create a handle on the external one; then it worked again. The old installed build was running throughout and holds a user client on the node. Recorded on `RR9`; not reproduced.

## Review

Second pass findings are in `docs/reviews/F1.md` § Second pass; this retrofit is their fix. It gets its own adversarial pass only if the owner asks: it is the fix of a review, not a feature.
