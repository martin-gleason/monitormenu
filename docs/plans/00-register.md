# Register — SwitchBar

Created: 2026-10-19 17:34 -05:00 · Edited: 2026-10-19 17:57 -05:00

Every register for this project, one `##` per register. This is the "where are we" read.

Append-only. Decisions are immutable once ratified; supersede, never edit.

---

## Decisions (D)

ADR-style: numbered, dated, **immutable once ratified**. **One intake path.** Anything that changes scope enters as a `D<n>`. An item with no number has not been decided, however clearly it was said aloud.

| ID | Status | Milestone | Decision |
|---|---|---|---|
| D1 | proposed | MVP | DDC/CI is spoken directly over IOKit's `IOAVService` I2C interface on Apple silicon, the same path m1ddc and MonitorControl use. No helper app. Why: BetterDisplay's CLI failed every single-value DDC read and write on this Mac on 2026-10-19, and a dependency on a running third-party app defeats "fast and convenient". |
| D2 | proposed | MVP | Layout mirrors HueBar and DockWatch: `SwitchCore` library (no AppKit, fully testable) + thin `SwitchBar` AppKit executable + `switchctl` command-line executable + `scripts/build-app.sh`. SwiftPM, no Xcode project. |
| D3 | proposed | MVP | The monitor's capabilities string is the whitelist. The app offers and writes only the VCP codes and values it advertises, and never exposes 0x04, 0x05, 0x08 (factory resets). Unknown values are shown as raw hex, never guessed at. |
| D4 | proposed | MVP | The built-in display is excluded. It has no DDC channel and macOS already controls its brightness. |
| D5 | proposed | MVP | Name: **SwitchBar**, bundle id `dev.marty.SwitchBar`, repo `martin-gleason/switchbar`. Chosen by the agent; the owner may rename before the first commit (`O4`). |
| D6 | proposed | MVP | External automation surface is a `switchbar://` URL scheme plus the `switchctl` binary. Both call the same `SwitchCore` actions as the menu. |
| D7 | proposed | MVP | Prior art reviewed 2026-10-19 (`docs/learnings/2026-10-19-prior-art.md`). SwitchBar's uncovered ground is PiP/PbP from the menu bar and the D3 whitelist; input switching with hotkeys and a CLI already exists in OpenDisplay, Lunar and m1ddc. m1ddc's documented Dell values label 0x00, 0x21, 0x22 and 0x24 of the G3223D's PiP modes; the other six stay hex until `O5`. |
| D8 | ratified | MVP | **Vision sentence rewritten by the owner 2026-10-19:** "Control your monitor from your desktop, menubar, or shortcut." Pasted into the spec by the agent on the owner's instruction. Replaces the agent-punctuated draft "SwitchBar allows fast, convenient switching of monitor inputs and functions right from the desktop, the menu bar, or a menu switcher." Adds FR9 (ships with a shortcut) and NFR8 (monitor neutral). |
| D9 | proposed | MVP | "Shortcut" means four surfaces, all calling the same `SwitchCore` actions: a global hotkey (Carbon `RegisterEventHotKey`, default ⌃⌥⌘I, overridable in `UserDefaults`); App Intents with an `AppShortcutsProvider` so actions appear in the Shortcuts app and Siri with no setup; the `switchbar://` URL scheme for Alfred, Raycast and scripts; the `switchctl` binary. App Intents metadata in a SwiftPM-built bundle needs `appintentsmetadataprocessor` run from `scripts/build-app.sh`; if that cannot be made to work inside F1-T5, the fallback is a bundled signed `.shortcut` wrapping the URL scheme, recorded as its own `D<n>`. |
| D10 | proposed | MVP | Monitor neutral (NFR8). The HP Omen the owner expects within 90 days of 2026-10-19 is the second test monitor; until it arrives, two-display matching is tested with a fixture, not hardware (`O10`). |

## Risks (RR)

| ID | Risk | Status | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|---|
| RR1 | `IOAVService` is undocumented. A macOS update can change or remove it, and an app using it is not App Store eligible. | open | Medium over years | App stops working after an OS update | Transport isolated behind one protocol in `SwitchCore`; live check on this Mac; App Store already out of scope. | agent |
| RR2 | Single-value DDC reads and writes through BetterDisplay failed on this Mac while the full capabilities scan succeeded. Cause unknown; may indicate a flaky I2C link on HDMI 1. | open | Observed 2026-10-19 | Switches silently fail or need retries | F1-T1 measures raw I2C reliability first and adds bounded retries; result recorded in the plan. | agent |
| RR3 | After switching the monitor to another input, the Mac may lose the DDC channel (some monitors stop answering I2C on an inactive input). The Mac then cannot switch back. | open | Unknown for the G3223D | Owner must use the monitor's buttons or the other source to return | Tested in F1-T2 on the G3223D and documented. A "switch back after N seconds" option is a future `D<n>` if needed. | human |
| RR4 | A wrong VCP write can put a monitor into an odd state (factory reset, locked OSD). | open | Low with D3 | Monitor needs manual recovery | D3 whitelist + M1 mutation test. | agent |
| RR5 | Meaning of the G3223D's ten PIP/PBP values (VCP 0xE9) is not documented anywhere the agent could find. | open | Certain | PIP menu labels could be wrong | Hands-on mapping session with the owner at the monitor (`O5`); unmapped values shown as hex. | human |

## Owner items (O)

Outstanding items only the owner can close.

| ID | Item | P | Status |
|---|---|---|---|
| O1 | Ratify or rewrite the vision sentence in `docs/specs/SPEC.md`. | P1 | closed 2026-10-19 — owner: "The vision statement is: Control your monitor from your desktop, menubar, or shortcut." (D8) |
| O2 | Lock the learning level. Agent proposes **5%** (Swift is not in the owner's language set; same as HueBar and DockWatch). | P1 | open |
| O3 | Say what "from the desktop" and "a menu switcher" mean to you. The agent read them as FR6 (hotkey switcher) and FR7 (URL scheme + CLI for Raycast, Alfred, Shortcuts). | P0 | closed 2026-10-19 — owner: "can use Siri, Alfred, or shortcuts as well as a menu bar or hot key switch" (D9) |
| O4 | Confirm the name SwitchBar or pick another (D5). | P2 | open |
| O5 | Sit at the G3223D for ten minutes while the agent steps through the 0xE9 values and say what each one shows. Closes RR5. | P1 | open |
| O6 | Ratify D1–D6. | P2 | open |
| O7 | Create the GitHub repository and say whether it is public or private. C1-T6 waits on it. | P2 | open |
| O8 | Gate C1 and F1: the yes that opens the build. | P0 | closed 2026-10-19 — owner: "Go ahead with a monitor neutral native swift app" |
| O9 | With the installed app launched once, open the Shortcuts app and confirm SwitchBar's actions are listed; then ask Siri to run one. Only the owner can speak to Siri. Closes the live half of FR9. | P1 | open |
| O10 | When the HP Omen arrives, connect both monitors and run the live check; paste `switchctl list`. Closes two-display matching (D10). | P2 | open |

## Agent items (A)

Outstanding items only the agent can close: defects in its own work, findings it owes a fix.

| ID | Item | P | Status |
|---|---|---|---|

## Chores (C)

| ID | Chore | P | Status | Owner | Plan |
|---|---|---|---|---|---|
| C1 | Build the harness: run, count, floor, mutate, pre-commit; CI once pushed. | P0 | open | agent | `docs/plans/C1.md` |

## Gates (G)

A gate is an **event**, not a place. It is recorded here so it exists outside the conversation where it happened.

| ID | Gate | Status | Plan written | Crossed | What the owner said |
|---|---|---|---|---|---|
| G1 | C1 harness | done (crossed) | 2026-10-19 | 2026-10-19 | "Go ahead with a monitor neutral native swift app" |
| G2 | F1 inputs, picture functions and PiP from the menu bar | done (crossed) | 2026-10-19 | 2026-10-19 | "Go ahead with a monitor neutral native swift app" |

## Hooks (H)

Deterministic enforcement. Prose is advisory; hooks are not. An `H<n>` is a plan-local label and **never appears in a commit, branch, or PR title**.

| ID | Hook | Surface | Protects | Status |
|---|---|---|---|---|
| H1 | `swift test` passes | pre-commit + CI | the test gate | not built (C1-T3, C1-T6) |
| H2 | Assertion count not below `Tests/ASSERTION_FLOOR` | pre-commit + CI | a suite that silently shrank | not built (C1-T2) |
| H3 | No register ID in a commit, branch or PR title | commit-msg | the two-tier grammar | not built (C1-T3) |
| H4 | Harness declared and its commands run | upstream `check_harness.py --run` | an undeclared or dead harness | not built (C1-T5) |
| H5 | Every FR has a test or a named manual check with evidence | plan review checklist | drift, both directions | open (manual checklist, no mechanism) |
| H6 | Nothing outside the capabilities whitelist is ever written | `swift test` (M1) | the monitor, from a bad write | not built (F1-T1) |
| H7 | Status page regenerates clean | pre-commit + CI | a stale status page | not built (C1-T3, C1-T6) |

## Mutations (M)

Named ways to break the code, each paired with the test that must catch it. A test is not evidence until a mutation proves it can fail.

| ID | File | Mutation | Caught by | Status |
|---|---|---|---|---|
| M1 | `Sources/SwitchCore/VCPWriter.swift` | Remove the capabilities check before a VCP write | `WhitelistTests.testUnadvertisedCodeIsRefusedBeforeAnyI2C` | proposed |
| M2 | `Sources/SwitchCore/Capabilities.swift` | Mis-parse nested parentheses in the capabilities string (`vcp(... 60(1B 0F 11 12) ...)`) | `CapabilitiesTests.testParsesG3223DFixture` | proposed |
| M3 | `Sources/SwitchCore/VCPReply.swift` | Read the input code from the high byte of the 0x60 reply instead of the low byte | `VCPReplyTests.testCurrentInputIsLowByte` | proposed |
| M4 | `Sources/SwitchCore/VCPWriter.swift` | Let a factory-reset code (0x04, 0x05, 0x08) through when the monitor advertises it | `WhitelistTests.testFactoryResetCodesAreNeverOffered` | proposed |
