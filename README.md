# MonitorMenu

Control your monitor from your desktop, menubar, or shortcut.

A native Mac menu bar app that talks DDC/CI to your external monitors directly: switch inputs, set brightness and contrast, turn picture-in-picture on, put the panel to sleep. No helper apps. Apple silicon, macOS 14 or later.

## Install

```
scripts/build-app.sh --install     # builds, signs (ad hoc), installs ~/Applications/MonitorMenu.app, links monitorctl
open -a MonitorMenu
```

## Use it

- **Menu bar**: click the display icon. Each monitor lists its inputs (the active one is checked), brightness and contrast sliders, Picture-in-Picture where the monitor has it, and Put Display to Sleep.
- **Hotkey**: ⌃⌥⌘I opens the input switcher; press a number. Change it with `defaults write dev.marty.MonitorMenu hotkey "ctrl+opt+cmd+i"` and relaunch.
- **Shortcuts and Siri**: the actions Switch Monitor Input, Set Monitor Brightness, Set Monitor Contrast, Set Picture-in-Picture, Put Monitor to Sleep and Open Input Switcher appear in the Shortcuts app after the first launch. Siri phrases: "Switch my monitor to HDMI 2 with MonitorMenu", "Open the MonitorMenu switcher", "Put my monitor to sleep with MonitorMenu".
- **URL scheme** (Alfred, Raycast, scripts): `open "monitormenu://input/hdmi2"`, `monitormenu://brightness/60`, `monitormenu://contrast/70`, `monitormenu://pip/small|large|split|off`, `monitormenu://pip-source/hdmi1`, `monitormenu://sleep`, `monitormenu://switcher`. Add `?display=dell` to pick a monitor by name when more than one is connected.
- **Command line**: `monitorctl list`, `monitorctl set input hdmi2`, `monitorctl set brightness 60`, `monitorctl set pip small`, `monitorctl get input`, `monitorctl capabilities`, `monitorctl probe`. `--display <name or id>` picks a monitor.

Input names: `dp1` `dp2` `hdmi1` `hdmi2` `usbc`, or a raw code like `0x11`.

## Safety rule

MonitorMenu only offers and sends what your monitor advertises in its DDC capabilities string, and never sends factory-reset codes, even when advertised. Values the app cannot name are shown as hex rather than guessed.

## Known limits

- Switching the monitor to an input with no signal leaves you looking at a blank panel until the other source wakes it or you use the monitor's buttons. DDC may or may not still answer on an inactive input; this varies by monitor.
- Some monitor presets (HDR modes on Dells, for one) lock brightness and contrast; the sliders then show the locked value and writes are refused by the monitor.
- `monitorctl` and the app share the monitor's I2C bus. Running both at the same instant can make one of them retry.

## Development

`swift test` runs the offline suite. `MONITORMENU_LIVE=1 swift test` adds a read-only check against the attached monitor. `scripts/mutate.sh M1` proves a test can fail. See `docs/specs/SPEC.md` for the contract and `docs/plans/` for the build record.
