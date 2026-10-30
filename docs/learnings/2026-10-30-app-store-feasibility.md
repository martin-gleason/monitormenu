# Can MonitorMenu ship on the Mac App Store? Checked 2026-10-30

Created: 2026-10-30 09:25 -05:00 · Edited: 2026-10-30 09:20 -05:00

The owner asked to "begin step by step to get this app in the apple store." Step one was to check
whether the store would take it. It will not, for two independent reasons, and this file records the
evidence so the question is not re-opened from memory. `SPEC.md` already lists App Store distribution
out of scope and `RR1` already says the app is not eligible; what was missing was a test, not a belief.

## Reason 1 — the App Sandbox blocks the DDC channel (tested here)

Mac App Store apps must be sandboxed (App Store Review Guideline 2.4.5(i): "They must be appropriately
sandboxed"). The installed 1.0.1 bundle was copied to the session scratch directory, given the bundle id
`dev.marty.MonitorMenuSandboxTest` so it would not collide with the running app, and re-signed with the
Developer ID identity and one entitlement, `com.apple.security.app-sandbox`. Nothing else changed: same
binary, same monitor, same cable.

| Instance | Entitlements | Result (unified log, subsystem `dev.marty.MonitorMenu`) |
|---|---|---|
| Installed app, pid 62243 | hardened runtime only | `discovery → 1 monitor(s) in 600 ms` |
| Sandboxed copy, pid 76730 | + `app-sandbox` | `discovery → 0 monitor(s) in 22 ms`, then `0 monitor(s)` at 3.4 s and 6.6 s |

Discovery returns in tens of milliseconds because the IOKit lookup that finds the display's
`IOAVService` yields nothing inside the sandbox; there is no DDC read to be slow. The sandboxed copy
was quit after the third discovery; no crash report was written for it. (A first attempt signed the bare
`monitorctl` binary outside a bundle; it died with `SIGTRAP` in `_libsecinit_appsandbox` before any of
our code ran, because a sandboxed executable needs a bundle for its container. That attempt says nothing
about DDC and is noted only so it is not repeated.)

This agrees with every DDC app surveyed in `2026-10-19-prior-art.md`: none is on the store, and Glint's
README says why in one line, "DDC requires direct I2C communication through IOKit, which is blocked by
the App Store sandbox."

## Reason 2 — `IOAVService` is not public API (no test needed)

Guideline 2.5.1: "Apps may only use public APIs." `IOAVServiceCreateWithService`, `IOAVServiceReadI2C`
and `IOAVServiceWriteI2C` appear in no SDK header; `Sources/CDDC/include/CDDC.h` declares them `extern`
by hand. App Store Connect's upload scan compares a binary's imported symbols against the public API
list and refuses non-public symbols (error ITMS-90338) before a human reviewer sees the app. Apple
silicon has no public replacement: Intel Macs had `IOI2CSendRequest` through the framebuffer, Apple
silicon exposes DDC only through this private service. A sandbox exception entitlement, if Apple ever
granted one, would not change this half.

## What is left

- **A store build with the DDC path removed** would pass review and do nothing; the vision sentence is
  "Control your monitor from your desktop, menubar, or shortcut" and every verb is DDC. Not proposed.
- **Direct distribution, done the way Apple expects for this category:** Developer ID signature (have),
  hardened runtime (have), notarization and stapling (`C6`, waits on `O16` credentials), a `.dmg` on
  GitHub Releases, and a Homebrew cask so `brew install --cask monitormenu` works. This is how
  MonitorControl, Lunar and BetterDisplay all ship. Proposed as `D23`.
- **The owner's account is ready either way:** a "Developer ID Application: Martin Gleason" identity is
  in the keychain, which means paid Developer Program membership and access to `notarytool`.

## Sources

- Apple, App Store Review Guidelines, 2.4.5 and 2.5.1 — https://developer.apple.com/app-store/review/guidelines/
- Glint README, "Why not the Mac App Store?" — https://github.com/blaineam/Glint/blob/main/README.md
- Test artefacts (session scratch, not committed): the re-signed bundle, `sandbox.entitlements`,
  the launch timestamp, and the log excerpts quoted above.
