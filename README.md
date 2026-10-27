# MonitorMenu

Created: 2026-10-19 19:22 -05:00 · Edited: 2026-10-27 09:54 -05:00

[![ci](https://github.com/martin-gleason/monitormenu/actions/workflows/ci.yml/badge.svg)](https://github.com/martin-gleason/monitormenu/actions/workflows/ci.yml)

**Control your monitor from your desktop, menubar, or shortcut.**

A native Mac menu bar app that talks DDC/CI to your external monitors directly: switch inputs, set brightness and contrast, turn picture-in-picture on, put the panel to sleep. No helper apps. Apple silicon, macOS 14 or later.

## Install

```
scripts/build-app.sh --install     # builds, signs with your Developer ID, installs ~/Applications/MonitorMenu.app, links monitorctl
open -a MonitorMenu
```

## Use it

- **Menu bar**: click the display icon. Each monitor lists its inputs (the active one is checked), brightness and contrast sliders, Picture-in-Picture where the monitor has it, and Put Display to Sleep.
- **Hotkey**: ⌃⌥⌘I opens the input switcher; press a number. Change it with `defaults write dev.marty.MonitorMenu hotkey "ctrl+opt+cmd+i"` and relaunch.
- **Shortcuts and Spotlight**: the actions Switch Monitor Input, Set Monitor Brightness, Set Monitor Contrast, Set Picture-in-Picture, Put Monitor to Sleep and Open Input Switcher appear in the Shortcuts app under MonitorMenu and in Spotlight.
- **Siri**: not in this version. The macOS 27 Siri (the one with the beta label) runs third-party actions only through Apple's App Schema domains, and there is none for displays, so it refuses every phrase ("I can't change that setting in MonitorMenu"). The phrases are in place for when a route opens (see `Sources/MonitorMenu/Voice.swift`): "Open the MonitorMenu switcher", "Switch my monitor to HDMI 2 with MonitorMenu", "Set picture in picture to small window with MonitorMenu", "Put my monitor to sleep with MonitorMenu", "Set my monitor brightness with MonitorMenu", "Set my monitor contrast with MonitorMenu". Until then, a shortcut you make yourself around one of the actions runs from the Shortcuts app and its menu bar item.
- **URL scheme** (Alfred, Raycast, scripts): `open "monitormenu://input/hdmi2"`, `monitormenu://brightness/60`, `monitormenu://contrast/70`, `monitormenu://pip/small|large|split|off`, `monitormenu://pip-source/hdmi1`, `monitormenu://sleep`, `monitormenu://switcher`, `monitormenu://rename/Desk` (`rename/-` clears the name). Add `?display=desk` to pick a monitor when more than one is connected.
- **Name your monitors**: Rename… under a monitor in the menu, or `monitorctl rename "Desk"` (`--clear` removes it). The name follows the monitor's serial number and is used by the menu, the switcher, Shortcuts, Siri, URLs and `monitorctl`. A selector (`--display`, `?display=`, the Monitor field in Shortcuts) is matched in this order: exact name you gave, serial, display id, exact model name, then part of your name, then part of the model name. A selector that fits two monitors is refused rather than guessed.
- **Command line**: `monitorctl list`, `monitorctl set input hdmi2`, `monitorctl set brightness 60`, `monitorctl set pip small`, `monitorctl get input`, `monitorctl capabilities`, `monitorctl probe`. `--display <name or id>` picks a monitor. A call takes about a quarter of a second: the monitor's capabilities string is read once and remembered per serial, shared with the app. `monitorctl capabilities` always reads it again; `--fresh` makes any command do so; Rescan Displays in the menu does the same for the app.

Input names: `dp1` `dp2` `hdmi1` `hdmi2` `usbc`, or a raw code like `0x11`.

## Safety rule

MonitorMenu only offers and sends what your monitor advertises in its DDC capabilities string, and never sends factory-reset codes, even when advertised. Values the app cannot name are shown as hex rather than guessed.

## Known limits

- Switching the monitor to an input with no signal leaves you looking at a blank panel until the other source wakes it or you use the monitor's buttons. DDC may or may not still answer on an inactive input; this varies by monitor.
- Some monitor presets lock brightness and contrast in the monitor itself. On a Dell with Smart HDR on, the sliders are greyed out with "Locked by the monitor's Smart HDR — turn it off in the monitor's menu", and `monitorctl set brightness` prints the same instead of sending a write the monitor would ignore. Other makers' presets are not recognised yet; their sliders stay live and the monitor ignores the write.
- `monitorctl` and the app share the monitor's I2C bus. Running both at the same instant can make one of them retry.

## Development

`swift test` runs the offline suite. `MONITORMENU_LIVE=1 swift test` adds a read-only check against the attached monitor. `scripts/mutate.sh M1` proves a test can fail. The app logs discovery and refresh timings and every failed action: `/usr/bin/log show --last 10m --predicate 'subsystem == "dev.marty.MonitorMenu"' --info --style compact` (the full path matters: zsh has its own `log` builtin). See `docs/specs/SPEC.md` for the contract and `docs/plans/` for the build record.
