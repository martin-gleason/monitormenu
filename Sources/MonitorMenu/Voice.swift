// Created: 2026-10-27 09:26 -05:00 · Edited: 2026-10-27 09:26 -05:00
import AppIntents

// Voice activation — the seam for v1.5 (D15).
//
// What works today: every intent in Intents.swift runs from the Shortcuts app, Spotlight and a shortcut
// of the user's own; the phrases below also appear in the Shortcuts app's gallery for this app. The
// `AppShortcutsProvider` is handed to the system at launch (`updateAppShortcutParameters()` in
// `AppDelegate`), which is what Siri needs from an app and is already done.
//
// What does not: the macOS 27 Siri (the one with the beta label) executes third-party actions only
// through App Schema domains (messages, calendar, audio, photos, …) and there is no domain for
// displays, so it answers "I can't change that setting in MonitorMenu" to every phrase here
// (`docs/learnings/2026-10-23-siri-app-intents.md`, two research runs). The app is not at fault; the
// owner moved voice to v1.5.
//
// The three routes v1.5 can take, each a change confined to this file plus a plan:
//   1. Siri Classic — reported to live under System Settings › Screen Time › Content & Privacy › Siri ›
//      Allowed Siri Version. Unverified on this Mac (a claim about another system is not ratifiable until
//      it has run); if it exists and works, there is nothing to build and the phrases are used as written.
//   2. Shipped shortcut files — signed `.shortcut` files wrapping the URL scheme (`monitormenu://…`),
//      imported once by the user, named so Siri's "run <name>" path finds them. Built with `plistlib`
//      and `shortcuts sign --mode anyone`; prototypes exist in the 2026-10-25 session notes.
//   3. An App Schema domain — if Apple adds one that fits a display, conform each intent with the
//      `@AssistantIntent(schema: …)` macro here, next to the phrase that names it. Until a domain
//      exists there is nothing to conform to, and the macro is not stubbed.

/// FR9: these phrases appear in Spotlight and the Shortcuts app on first launch, and are what Siri would
/// use once a route above is open. Each phrase names the app: Siri routes anything else to HomeKit.
struct MonitorMenuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SwitchInputIntent(),
                    phrases: ["Switch my monitor to \(\.$input) with \(.applicationName)", "\(.applicationName) switch to \(\.$input)"],
                    shortTitle: "Switch Input", systemImageName: "display")
        AppShortcut(intent: OpenSwitcherIntent(),
                    phrases: ["Open the \(.applicationName) switcher", "Switch monitor input with \(.applicationName)"],
                    shortTitle: "Input Switcher", systemImageName: "rectangle.on.rectangle")
        AppShortcut(intent: SleepMonitorIntent(),
                    phrases: ["Put my monitor to sleep with \(.applicationName)"],
                    shortTitle: "Sleep Monitor", systemImageName: "moon")
        AppShortcut(intent: SetPiPIntent(),
                    phrases: ["Set picture in picture to \(\.$mode) with \(.applicationName)"],
                    shortTitle: "Picture-in-Picture", systemImageName: "pip")
        // A number cannot ride in a phrase; Siri asks for it after the phrase (review O9, 2026-10-23).
        AppShortcut(intent: SetBrightnessIntent(),
                    phrases: ["Set my monitor brightness with \(.applicationName)", "\(.applicationName) brightness"],
                    shortTitle: "Brightness", systemImageName: "sun.max")
        AppShortcut(intent: SetContrastIntent(),
                    phrases: ["Set my monitor contrast with \(.applicationName)", "\(.applicationName) contrast"],
                    shortTitle: "Contrast", systemImageName: "circle.lefthalf.filled")
    }
}
