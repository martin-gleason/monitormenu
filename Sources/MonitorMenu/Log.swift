// Created: 2026-10-27 10:05 -05:00 · Edited: 2026-10-27 09:54 -05:00
import os

/// The app's log (review C4 #2): `NSLog` text is redacted to `<private>` in the unified log, so no timing
/// line or error was readable with `log show`. Timings, flags and outcomes are marked public; monitor names
/// and serials stay private. Read with:
///   /usr/bin/log show --last 10m --predicate 'subsystem == "dev.marty.MonitorMenu"' --info --style compact
/// (the full path: zsh has a builtin named `log` that silently answers instead)
enum Log {
    static let app = Logger(subsystem: "dev.marty.MonitorMenu", category: "app")
}
