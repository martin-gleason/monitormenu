# F1d — Adversarial review log

Created: 2026-10-29 12:25 -05:00 · Edited: 2026-10-29 12:25 -05:00

**Reviewer:** fresh-context subagent running `.claude/agents/adversarial-reviewer.md`, 2026-10-29 12:20–12:27, on branch `F1d/pip-names` at `5ea03fd` (`main..HEAD`, 4 commits). It built, ran the suite (43/43), killed M14, ran `monitorctl list`, `list --json`, `get pip` and `get 0xE9` against the live G3223D, replicated the URL handler's path parsing in a scratch script, and checked commit timestamps, stamps, the status page and the version in both places. No write to the monitor.

**Verdict as given:** fix first, then merge. Nothing critical or major: NFR5 holds, no path bypasses `pipModes()`, the six-mode list is right on the live monitor; four cheap user-facing gaps and five record-keeping items to correct on the branch.

## Findings and what was done

| # | Sev | Finding | Outcome |
|---|---|---|---|
| 1 | minor | A hidden current mode (the CLI's `set pip 0x2D`) leaves the PiP submenu with nothing ticked: items exist only for the six offered values. | **fixed** — `VCP.pipTwins` maps a hidden duplicate to its offered twin; `MonitorStore` stores `VCP.shownPiPValue(…)`, so 0x2D ticks "PbP 25/75"; test in `VCPTests` |
| 2 | minor | `monitormenu://pip/25/75` split at the slash and sent `25` (decimal 0x19, refused); only `25-75` or `25%2F75` worked, undocumented. | **fixed** — the `pip` verb takes the whole path; README and the handler's comment list `pip/25/75` |
| 3 | minor | The new words and the "this Mac's share first" rule appeared nowhere a user reads: `monitorctl` usage and error text, `Actions.setPiP` doc, README. | **fixed** — all four updated; README gains a PiP ratios line that also explains hidden values |
| 4 | minor | `PiPChoice` (Shortcuts, Spotlight) was a fixed four-case enum; two of the six layouts unreachable. | **fixed** — cases `25/75` and `75/25`, shown as "Side by side, this Mac 25%" / "75%" |
| 5 | minor | `set pip 0x2D` prints the same confirmation as `set pip 25/75`; `set pip 0x01` reports success though the firmware drops it; `set` never reads back. | **accepted** — `get pip` shows the hex; a read-back after `set` is a design change for every verb (`D22`'s plan can take it up) |
| 6 | minor (process) | Plan committed 112 s before the code with its status already "built the same day". | **on the record** — process note in `docs/plans/F1d.md` |
| 7 | minor (process) | The register gained five rows with its stamp unchanged. | **fixed** — stamped with `stamp.py` |
| 8 | minor (process) | M14's cell read `run — killed …`; the status generator recognises a cell that starts with `killed`, so M10–M14 counted as unknown. | **fixed** — the five cells now start with `killed`; status page regenerated |
| 9 | minor (process) | The learning said 0x29 "looked different" from PiP small without saying what was seen; "all three 50/50-class modes" was unclear; an evidence row quoted `get`'s format for `set`. | **fixed** — the first pass's reports are recorded beside the second, the 0xEA sentence names the four modes, the evidence row shows both commands |
| 10 | minor | The M9 doc comment attached to the new test. | **fixed** — moved back to `testContinuousWriteReadsTheMaximumFirst` |
| 11 | minor (risk) | Hidden set keyed by vendor while the mapping is one model's; `Capabilities.model` would allow a (vendor, model) key. | **accepted** — consistent with `lockingPresets`; `D22` moves the list to the user; noted in the plan's risks |
| 12 | minor (process) | `Milestone: v1.0 (patch 1.0.1)` made the generator invent a milestone row. | **fixed** — `Milestone: v1.0 · Ships as: 1.0.1` |

Answered without a finding: NFR5 (the whitelist test records the `0xE9/0x2D` frame through the real capabilities string); every list consumer goes through `pipModes()`; commit subjects carry structural IDs only; version in both places; the filter's cost is negligible; no security surface changed.

## Verification after the fixes (2026-10-29)

| Check | Result | How |
|---|---|---|
| suite | see the PR description | `swift test` |
| M14 | pattern unchanged, re-run | `scripts/mutate.sh M14` |
| URL slash form | `monitormenu://pip/off` at the current value (Off) via the built bundle | after install |
