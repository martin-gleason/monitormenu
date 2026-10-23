# F1c — Siri phrases that Siri can hear

Created: 2026-10-23 10:40 -05:00 · Edited: 2026-10-23 10:40 -05:00

**Status:** built 2026-10-23; no gate (FR9 defect `A4`, found by the owner's `O9` check) · **Milestone:** v1.0 · **Owner:** agent · **Retrofits:** F1 (FR9)

Learning level 5%, locked (`O2`); every task is `owner: agent`.

## What the user gets

Siri runs the app's actions when asked with one of the app's phrases. Brightness and contrast gain phrases; Siri asks for the number, because a number cannot be part of a phrase.

### F1c-T1 — Register the phrases at launch; brightness and contrast phrases
Owner: agent · `MonitorMenuShortcuts.updateAppShortcutParameters()` in `applicationDidFinishLaunching`; two `AppShortcut`s added. Checkpoint: the owner says "Open the MonitorMenu switcher" and the switcher opens.

## Evidence (2026-10-23)

| Check | Result | How |
|---|---|---|
| build, suite | `Build complete`; 29 tests, 0 failures | `swift build`, `swift test` (pre-commit) |
| metadata carries six App Shortcuts | see the install log line `App Intents metadata: extract.actionsdata version.json` and the phrase list in the review of the bundle | `plutil -p …/Metadata.appintents/extract.actionsdata` |
| Siri hears a phrase | **owner** (`O9`) | voice |
