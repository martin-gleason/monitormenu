# MonitorMenu — SPEC

Control your monitor from your desktop, menubar, or shortcut.

Created: 2026-10-19 17:34 -05:00 · Edited: 2026-10-19 17:34 -05:00

> **Vision sentence status: ratified. The owner's own sentence of 2026-10-19 (D8), pasted here on the owner's instruction; the earlier agent-punctuated draft is in the register's D8 row.**

## Functional requirements

| ID | Requirement |
|---|---|
| FR1 | The menu bar menu lists every connected external display that answers DDC/CI, by the name the monitor reports. Displays that do not answer (including the built-in display) are not listed. |
| FR2 | Each display lists the input sources it advertises, with the active input checked. Selecting one switches the monitor to that input. |
| FR3 | Each display's brightness and contrast can be set from the menu, showing the current value. |
| FR4 | On a display that advertises picture-in-picture or picture-by-picture, the menu offers the advertised modes and the secondary source. On a display that does not, the item is absent. |
| FR5 | Each display can be put to standby and woken from the menu. |
| FR6 | A global keyboard shortcut opens a compact switcher listing the inputs of the chosen display; a second keystroke selects one. |
| FR7 | Every action is reachable from outside the app by a URL scheme and a command-line entry point, so Raycast, Alfred, Shortcuts, or a script can trigger it. |
| FR8 | The menu reflects the monitor's actual state when opened and re-reads it after every action. |
| FR9 | The app ships ready to use: a default global hotkey opens the switcher, and its actions appear in the Shortcuts app and Siri without the user building anything. |
| FR10 | A monitor can be given a name of the user's choosing from the menu. The name is shown everywhere the monitor is named, matches `--display`, `?display=` and the Monitor parameter of every intent, persists across launches, is keyed by the monitor's serial, and can be cleared to return to the monitor's own name. *(v1.0, D13, pasted on the owner's instruction 2026-10-21.)* |

## Non-functional requirements

| ID | Requirement |
|---|---|
| NFR1 | Talks DDC/CI directly over IOKit. No dependency on BetterDisplay, MonitorControl, or any helper process. |
| NFR2 | Resident memory under 30 MB at idle. AppKit only; no polling timers. |
| NFR3 | No third-party dependencies. |
| NFR4 | A DDC transaction never blocks the UI and has a timeout; a failure surfaces as a brief non-modal message, never a crash or a hang. |
| NFR5 | The app writes only VCP codes and values the monitor advertises in its capabilities string. Factory-reset codes are never exposed. |
| NFR6 | macOS 14 or later, Apple silicon. Intel Macs are out of scope for MVP. |
| NFR7 | `MonitorCore` never imports AppKit. |
| NFR8 | Monitor neutral: no code path is specific to one vendor. Vendor-specific value labels live in a table consulted only when the capabilities string advertises the code. |

## Hook intentions

- Every FR has a test or a named manual check, recorded in the feature plan.
- `swift test` is the harness; the offline tests must pass on every change.
- The capabilities whitelist (NFR5) has a test that fails when the check is removed.

## Out of scope for MVP (future milestones, enter via `D<n>`)

Named presets ("Work", "Console") · schedules and automation rules · the built-in display's brightness · Intel Macs · volume and speaker controls · color temperature and RGB gain · multiple-monitor profiles · App Store distribution.

## Reference hardware

Dell G3223D on HDMI 1 of this Mac, capabilities string captured 2026-10-19 via BetterDisplay (kept as a test fixture in F1). It advertises inputs `60(1B 0F 11 12)`, PIP/PBP mode `E9(00 01 02 21 22 24 29 2A 2D 2E)`, PIP sub-source `EA`, and power `D6(01 04 05)` (VCP code 0xD6).

## Stack

Baseline. Changing any of this is a `D<n>`.

- language: Swift 5.9 language mode on the installed Swift 6 toolchain
- framework: AppKit and IOKit, no SwiftUI; SwiftPM package, no Xcode project; macOS 14 or later; no third-party dependencies
- runner: `swift test` (XCTest)
- layout: `Sources/MonitorCore` (library, no AppKit) · `Sources/MonitorMenu` (menu bar executable) · `Sources/monitorctl` (command-line executable) · `Tests/MonitorCoreTests`
- ci: GitHub Actions on macOS once the repository is pushed; `.githooks/pre-commit` locally until then
