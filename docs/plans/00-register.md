# Register — MonitorMenu

Created: 2026-10-19 17:34 -05:00 · Edited: 2026-10-22 15:00 -05:00

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
| D5 | superseded by D12 | MVP | Name: **SwitchBar**, bundle id `dev.marty.SwitchBar`, repo `martin-gleason/switchbar`. Chosen by the agent; the owner may rename before the first commit (`O4`). |
| D6 | proposed | MVP | External automation surface is a `switchbar://` URL scheme plus the `switchctl` binary. Both call the same `SwitchCore` actions as the menu. |
| D7 | proposed | MVP | Prior art reviewed 2026-10-19 (`docs/learnings/2026-10-19-prior-art.md`). SwitchBar's uncovered ground is PiP/PbP from the menu bar and the D3 whitelist; input switching with hotkeys and a CLI already exists in OpenDisplay, Lunar and m1ddc. m1ddc's documented Dell values label 0x00, 0x21, 0x22 and 0x24 of the G3223D's PiP modes; the other six stay hex until `O5`. |
| D8 | ratified | MVP | **Vision sentence rewritten by the owner 2026-10-19:** "Control your monitor from your desktop, menubar, or shortcut." Pasted into the spec by the agent on the owner's instruction. Replaces the agent-punctuated draft "SwitchBar allows fast, convenient switching of monitor inputs and functions right from the desktop, the menu bar, or a menu switcher." Adds FR9 (ships with a shortcut) and NFR8 (monitor neutral). |
| D9 | proposed | MVP | **Built as written; the fallback was not needed** — `appintentsmetadataprocessor` runs from `scripts/build-app.sh` on the `.swiftconstvalues` this toolchain's SwiftPM emits, and `Metadata.appintents/extract.actionsdata` lists all six intents and the Siri phrases. "Shortcut" means four surfaces, all calling the same `SwitchCore` actions: a global hotkey (Carbon `RegisterEventHotKey`, default ⌃⌥⌘I, overridable in `UserDefaults`); App Intents with an `AppShortcutsProvider` so actions appear in the Shortcuts app and Siri with no setup; the `switchbar://` URL scheme for Alfred, Raycast and scripts; the `switchctl` binary. App Intents metadata in a SwiftPM-built bundle needs `appintentsmetadataprocessor` run from `scripts/build-app.sh`; if that cannot be made to work inside F1-T5, the fallback is a bundled signed `.shortcut` wrapping the URL scheme, recorded as its own `D<n>`. |
| D10 | proposed | MVP | Monitor neutral (NFR8). The HP Omen the owner expects within 90 days of 2026-10-19 is the second test monitor; until it arrives, two-display matching is tested with a fixture, not hardware (`O10`). |
| D11 | proposed | MVP | `switchctl` has no raw `set <code> <value>`; writes are limited to the spec's controls (input, brightness, contrast, power, PiP mode and source). Raw `get 0xNN` stays for diagnosis. Source: review K2. The volume round-trip used as write-path evidence on 2026-10-19 was made with the command before it was removed. |
| D12 | ratified | MVP | **Supersedes D5.** The owner named it **MonitorMenu** on 2026-10-19: "Name is MonitorMenu". Bundle id `dev.marty.MonitorMenu`, URL scheme `monitormenu://`, library `MonitorCore`, command line `monitorctl`, repo `martin-gleason/monitormenu`. Register rows, the review log and the learnings keep the old name as the historical record. |
| D13 | ratified | v1.0 | **Milestone v1.0 follows MVP** and opens with F2, naming monitors (owner, 2026-10-20: "monitormenu should allow for renaming of devices -- can we add that to v1.0"). Adds FR10 (`docs/plans/F2.md`). Names live in `UserDefaults` keyed by the monitor's serial and are used everywhere the monitor is named. |

## Risks (RR)

| ID | Risk | Status | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|---|
| RR1 | `IOAVService` is undocumented. A macOS update can change or remove it, and an app using it is not App Store eligible. | open | Medium over years | App stops working after an OS update | Transport isolated behind one protocol in `SwitchCore`; live check on this Mac; App Store already out of scope. | agent |
| RR2 | Single-value DDC reads and writes through BetterDisplay failed on this Mac while the full capabilities scan succeeded. Cause unknown; may indicate a flaky I2C link on HDMI 1. | resolved 2026-10-19 — the link is fine: `switchctl probe` 100/100 reads, mean 117 ms; 30/30 cold-process reads of 0xDF correct; m1ddc 1.2.0 also misreads this monitor, so the fault was in those tools' timing, not the cable | Observed 2026-10-19 | Switches silently fail or need retries | F1-T1 measures raw I2C reliability first and adds bounded retries; result recorded in the plan. | agent |
| RR3 | After switching the monitor to another input, the Mac may lose the DDC channel (some monitors stop answering I2C on an inactive input). The Mac then cannot switch back. | open | Unknown for the G3223D | Owner must use the monitor's buttons or the other source to return | Tested in F1-T2 on the G3223D and documented. A "switch back after N seconds" option is a future `D<n>` if needed. | human |
| RR4 | A wrong VCP write can put a monitor into an odd state (factory reset, locked OSD). | open | Low with D3 | Monitor needs manual recovery | D3 whitelist + M1 mutation test. | agent |
| RR5 | Meaning of the G3223D's ten PIP/PBP values (VCP 0xE9) is not documented anywhere the agent could find. | open | Certain | PIP menu labels could be wrong | Hands-on mapping session with the owner at the monitor (`O5`); unmapped values shown as hex. | human |

| RR6 | The G3223D reports brightness 0/100 and contrast 100/100 and refuses writes to both, while every other code reads correctly and volume round-trips. Between BetterDisplay's 17:19 scan (56/75) and 18:10 the Dell preset code 0xF0 moved 0x0F → 0x34 and 0xE2 0x20 → 0x27, and 0xF0 refuses a write back. Looks like the monitor entered an HDR or locked preset while BetterDisplay was running. **Recurred 2026-10-23 09:30:** same signature to the byte (`60 ← 1B 1B 1B 1B`, brightness 0/100, contrast 100/100, preset `0xF0` = 0x34, `0xE2` = 0x27), minutes after the freshly installed app's startup discovery overlapped a `monitorctl` read on the bus (the CLI got null messages) and about 25 minutes after a PiP on/off cycle. No preset write from this side, ever. Common factor with 2026-10-19: two processes on the DDC bus at once. Owner asked to read the OSD before anything clears it (`O11` reopened). | resolved 2026-10-19 — brightness 56/100, contrast 75/100, input HDMI 1 and 0xF0 = 0x0F all came back by 20:00, after the agent's first PiP on/off cycle through the app; cause not proven (RR6 note in `O11`) | Observed 2026-10-19 | FR3 could not be verified live for two hours | If it recurs: a PiP on/off cycle, or the OSD. | human |
| RR7 | Input switching cannot be verified by the agent alone: switching the monitor away from the Mac's input may leave it on a source with no signal (RR3), and only a person at the desk can switch back if DDC stops answering. | open | Certain | FR2 live check waits on the owner | `O12`: the owner runs the first switch with a second source attached and the monitor's buttons within reach. | human |
| RR8 | `switchctl` and the app share one I2C bus. Both transacting at the same instant corrupts one side's read (observed: `switchctl` got null messages while the app handled a URL). | open | Low in normal use | A CLI read fails or needs a retry | Five attempts with a doubling pause (F1-T5); README documents it. A single broker process is a future `D<n>` if it bites. | agent |
| RR9 | A PiP or input change makes the G3223D retrain its link a few seconds later: it leaves CoreGraphics, sometimes the IORegistry for several seconds, and the `IOAVService` handle dies (`MACH_SEND_INVALID_DEST`). The first build dropped the monitor for good; the next action after any such change fails on the stale handle. | resolved 2026-10-19 — capabilities cached by serial; fail fast on the dead handle; rediscover and retry up to three rounds; actions wait up to 8 s for a monitor; rediscovery pre-scheduled after input and PiP actions. Two full on/off cycles at 20:23 landed every action, each after one retry round. Cost: 3–8 s latency on the action after a PiP or input change. | Certain per change | Action after a PiP or input change fails or is slow | Built 2026-10-23 (`F1b-T1`, `A1`): the channel re-creates the handle per call and re-finds the service after a retrain, so the held `Monitor` keeps working; the wait is now only for the monitor itself to answer. Unexplained observation 2026-10-23 09:02–09:10: both `DCPAVServiceProxy` nodes were recreated with no action from this side and no handle could be created for about two minutes, then it recovered (`docs/plans/F1b.md` § Observation) | agent |

## Owner items (O)

Outstanding items only the owner can close.

| ID | Item | P | Status |
|---|---|---|---|
| O1 | Ratify or rewrite the vision sentence in `docs/specs/SPEC.md`. | P1 | closed 2026-10-19 — owner: "The vision statement is: Control your monitor from your desktop, menubar, or shortcut." (D8) |
| O2 | Lock the learning level. Agent proposes **5%** (Swift is not in the owner's language set; same as HueBar and DockWatch). | P1 | closed 2026-10-20 — owner: "we're locked to 5%" |
| O3 | Say what "from the desktop" and "a menu switcher" mean to you. The agent read them as FR6 (hotkey switcher) and FR7 (URL scheme + CLI for Raycast, Alfred, Shortcuts). | P0 | closed 2026-10-19 — owner: "can use Siri, Alfred, or shortcuts as well as a menu bar or hot key switch" (D9) |
| O4 | Confirm the name SwitchBar or pick another (D5). | P2 | closed 2026-10-19 — "Name is MonitorMenu" (D12) |
| O5 | Sit at the G3223D for ten minutes while the agent steps through the 0xE9 values and say what each one shows. Closes RR5. | P1 | open |
| O6 | Ratify D1–D6. | P2 | open |
| O7 | Create the GitHub repository and say whether it is public or private. C1-T6 waits on it. | P2 | closed 2026-10-19 — "you can craft the github page": created public by the agent as `martin-gleason/monitormenu`, matching HueBar and DockWatch; flip with `gh repo edit --visibility private` if the monitor serial in the docs bothers you |
| O8 | Gate C1 and F1: the yes that opens the build. | P0 | closed 2026-10-19 — owner: "Go ahead with a monitor neutral native swift app" |
| O9 | With the installed app launched once, open the Shortcuts app and confirm MonitorMenu's actions are listed (done 2026-10-22, see `A3`); then ask Siri to run one, for example "Hey Siri, set monitor brightness". Only the owner can speak to Siri. Closes the live half of FR9. | P1 | open — Shortcuts half done 2026-10-22; Siri half outstanding |
| O10 | When the HP Omen arrives, connect both monitors and run the live check; paste `switchctl list`. Closes two-display matching (D10). Also from the second review pass (2026-10-23), two things only two monitors can show: whether a refresh of one monitor overwrites the other's fresher values (`MonitorStore.refresh(only:)` merges the whole snapshot back), and whether two same-model monitors, one mid-retrain, end up sharing a display id or a serial key. Paste `monitorctl list --json` with both connected and after one PiP change. | P2 | open |
| O11 | Look at the Dell's on-screen menu: is Brightness greyed out, and is Smart HDR or a game preset on? Brightness reads 0 and refuses writes over DDC since about 18:00 on 2026-10-19 (RR6). | P1 | closed 2026-10-19 — resolved itself by 20:00 (56/75 back). One question remains for the owner: did you touch the monitor's buttons or see the screen go blank between 19:45 and 20:00? If not, the agent's PiP cycle cleared it. **Reopened 2026-10-23 09:36:** the state is back right now. Open the Dell's menu with its joystick: which preset mode is selected (Standard, Game, Smart HDR, Console, Creator…), and is Brightness greyed out? Say what you see before the agent cycles PiP, which coincided with the clear last time. |
| O12 | First live input switch, with you at the desk: connect a second source to HDMI 2 (or know where the monitor's input button is), then pick that input from the SwitchBar menu and switch back from the other side or the buttons. Closes FR2 live and answers RR3. | P1 | held 2026-10-20 — owner: \"I don't have a second source attached\". Waits for the HP Omen or any HDMI device; RR3 stays unanswered until then |
| O13 | Gate F2 (name your monitors, `docs/plans/F2.md`) and ratify D13, which also opens milestone v1.0 and adds FR10 to the spec (paste it in, or tell the agent to). | P1 | closed 2026-10-21 — "f2 and d13 are good to go"; FR10 pasted into the spec by the agent on that instruction |
| O14 | In the Shortcuts app, click All Actions, then the Apps list: look for **MonitorMenu** (six actions) and **IntentProbe** (one action, "Probe Monitor"). Report which of the two you see. Both are installed, signed with your Developer ID and running. | P0 | closed 2026-10-22 — the owner opened a new shortcut and searched the action library: both apps list their actions. |

## Agent items (A)

Outstanding items only the agent can close: defects in its own work, findings it owes a fix.

| ID | Item | P | Status |
|---|---|---|---|
| A1 | Re-create the `IOAVService` per transaction instead of holding one, so a link retrain never leaves a dead handle and the action after a PiP or input change stops paying 3–8 s of retries (RR9). Measure first: does `IOAVServiceCreateWithService` per call cost more than the retry? **Measured 2026-10-23:** lookup plus creation 0.5 ms; fresh handle per read 65 ms vs 61.5 ms held. Built as `F1b-T1`: the channel keeps the node id and display key, creates the handle per call and re-finds the service after a retrain; a `Monitor` held across a PiP change read brightness 9 s later in 788 ms. | P2 | closed 2026-10-23 |
| A2 | Second adversarial pass over the post-review fixes (`docs/reviews/F1.md` § Not re-reviewed). **Done 2026-10-23:** two majors (timeout retried on top of the abandoned call; one shared I/O pool dying at 64 abandoned calls), six minors; all fixed in `F1b` except one accepted (`docs/reviews/F1.md` § Second pass). Two two-monitor items moved to `O10`. | P1 | closed 2026-10-23 |
| A3 | **FR9 defect:** the Shortcuts app does not list MonitorMenu's actions. **2026-10-21:** the installed bundle was LaunchServices-flagged `quarantined` and ad-hoc signed; `scripts/build-app.sh` now signs with the Developer ID identity (team KH6NBQRZBY), strips quarantine and keeps one LS registration. Owner to look again (`O14`). **Bisect 2026-10-22:** a one-intent control app built and signed by Xcode (`IntentProbe`, installed beside MonitorMenu) has byte-for-byte equivalent intents metadata; the only remaining differences were Xcode's Info.plist platform and SDK keys (`DTPlatformName`, `DTSDKName`, `CFBundleSupportedPlatforms`, …) and two processor flags (`--bundle-identifier`, `--compile-time-extraction`). `build-app.sh` now writes and passes all of them. If Shortcuts lists IntentProbe but not MonitorMenu after this, the cause is outside the bundle. `Metadata.appintents` has all six actions, both enums and four App Shortcuts; the binary links AppIntents and keeps the intent types; no appintentsd log line mentions the bundle. Suspects: ad-hoc signature without a team id, two LaunchServices registrations (build/ and ~/Applications), or the SwiftPM binary missing something Xcode's link step adds. Next: unregister the build copy, relaunch, read appintentsd logs; then a minimal Xcode-built control app to bisect. **Outcome 2026-10-22:** the owner searched the action library in a new shortcut and both apps appear; MonitorMenu lists all six actions. Closed. Cause not isolated: the fix landed as one batch (Developer ID signature, quarantine strip, single LaunchServices registration, platform and SDK keys, the two processor flags) and the bisect stopped once the actions showed, so no single change is proven necessary. All of them stay in `build-app.sh`; none is costly. `IntentProbe` removed from `~/Applications`. | P0 | closed 2026-10-22 |

## Chores (C)

| ID | Chore | P | Status | Owner | Plan |
|---|---|---|---|---|---|
| C1 | Build the harness: run, count, floor, mutate, pre-commit; CI once pushed. | P0 | done 2026-10-19 — CI run 39354005338 green on main; ruleset Rebase-n-Merge active (PR + `test` check + rebase only) | agent | `docs/plans/C1.md` |
| C2 | Rename SwitchBar → MonitorMenu (D12): directories, identifiers, bundle id, URL scheme, CLI, docs; historical rows untouched. | P1 | done 2026-10-19 | agent | — |

## Gates (G)

A gate is an **event**, not a place. It is recorded here so it exists outside the conversation where it happened.

| ID | Gate | Status | Plan written | Crossed | What the owner said |
|---|---|---|---|---|---|
| G1 | C1 harness | done (crossed; closed 2026-10-19 with CI) | 2026-10-19 | 2026-10-19 | "Go ahead with a monitor neutral native swift app" |
| G2 | F1 inputs, picture functions and PiP from the menu bar | done (crossed) | 2026-10-19 | 2026-10-19 | "Go ahead with a monitor neutral native swift app" |
| G3 | F2 name your monitors | done (crossed) | 2026-10-20 | 2026-10-21 | "f2 and d13 are good to go. begin f2 and a3" |

## Hooks (H)

Deterministic enforcement. Prose is advisory; hooks are not. An `H<n>` is a plan-local label and **never appears in a commit, branch, or PR title**.

| ID | Hook | Surface | Protects | Status |
|---|---|---|---|---|
| H1 | `swift test` passes | pre-commit + CI | the test gate | built — pre-commit runs it on every commit (C1-T3); CI run 39354005338 green on main 2026-10-19 (C1-T6) |
| H2 | Assertion count not below `Tests/ASSERTION_FLOOR` | pre-commit + CI | a suite that silently shrank | built — refused a floor of 17 against 16 on 2026-10-19 (C1-T3); CI step `executed=20 floor=20` (C1-T6) |
| H3 | No register ID in a commit message, branch or PR title | commit-msg | the two-tier grammar | built — refused `fix(F1): closes D1 and RR2` (subject) and `Closes D1, RR2 and O5.` (body) on 2026-10-19; types limited to the conventions' seven (C1-T3, review X2) |
| H4 | Harness declared and its commands run | upstream `check_harness.py --run` | an undeclared or dead harness | built — reports `ok switchbar` 2026-10-19 (C1-T5) |
| H5 | Every FR has a test or a named manual check with evidence | plan review checklist | drift, both directions | open (manual checklist, no mechanism) |
| H6 | Nothing outside the capabilities whitelist is ever written | `swift test` (M1, M4) | the monitor, from a bad write | built — M1 and M4 killed 2026-10-19 (F1-T1) |
| H7 | Status page regenerates clean | pre-commit + CI | a stale status page | built — pre-commit runs `gen_status.py --check` (C1-T3); needs the upstream generator, so it stays local (C1-T6) |

## Mutations (M)

Named ways to break the code, each paired with the test that must catch it. A test is not evidence until a mutation proves it can fail.

| ID | File | Mutation | Caught by | Status |
|---|---|---|---|---|
| M1 | `Sources/SwitchCore/Monitor.swift` | Remove the capabilities check before a VCP write | `WhitelistTests.testUnadvertisedCodeIsRefusedBeforeAnyI2C` | killed 2026-10-19: 3 failures / 1 test (`scripts/mutate.sh M1`) |
| M2 | `Sources/SwitchCore/Capabilities.swift` | Mis-parse nested parentheses in the capabilities string (`vcp(... 60(1B 0F 11 12) ...)`) | `CapabilitiesTests.testParsesG3223DFixture` | killed 2026-10-19: 5 failures / 1 test (`scripts/mutate.sh M2`) |
| M3 | `Sources/SwitchCore/DDCProtocol.swift` | Read the current value from bytes 6–7 of the reply (the maximum) instead of 8–9 | `DDCFrameTests.testCurrentInputIsLowByte` | killed 2026-10-19: 2 failures / 1 test (`scripts/mutate.sh M3`) |
| M4 | `Sources/SwitchCore/Monitor.swift` | Let a factory-reset code (0x04, 0x05, 0x08) through when the monitor advertises it | `WhitelistTests.testFactoryResetCodesAreNeverOffered` | killed 2026-10-19: 4 failures / 1 test (`scripts/mutate.sh M4`) |
| M5 | `Sources/SwitchCore/DDCProtocol.swift` | Skip the reply checksum (a flipped byte becomes a value) | `DDCFrameTests.testChecksumMismatchIsRejected` | killed 2026-10-19: 2 failures / 1 test (`scripts/mutate.sh M5`) |
| M6 | `Sources/SwitchCore/I2CChannel.swift` | Wait forever for the I2C call instead of the deadline | `DDCFrameTests.testDeadlineChannelTimesOut` | killed 2026-10-19: 2 failures / 1 test (`scripts/mutate.sh M6`) |
| M7 | `Sources/MonitorCore/MonitorNames.swift` | Key names by CoreGraphics display id instead of serial | `MonitorNamesTests.testNamesAreKeyedBySerialNotDisplayID` | killed 2026-10-21: 3 failures / 1 test (`scripts/mutate.sh M7`) |
| M8 | `Sources/MonitorCore/DDCProtocol.swift` | Retry after a transport timeout (stacks a second call on the abandoned one) | `DDCFrameTests.testTimeoutIsNotRetried` | killed 2026-10-23 |
| M9 | `Sources/MonitorCore/Monitor.swift` | Write a continuous code without first learning its maximum | `WhitelistTests.testContinuousWriteReadsTheMaximumFirst` | killed 2026-10-23 |
