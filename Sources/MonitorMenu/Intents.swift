// Created: 2026-10-19 19:52 -05:00 · Edited: 2026-10-29 12:25 -05:00
import AppIntents
import AppKit
import MonitorCore

// FR7, FR9: App Intents make every action a Shortcuts action, a Spotlight action and, via the
// AppShortcutsProvider in Voice.swift, a Siri phrase. All call Actions.shared, the same path as the menu (D9).

enum InputChoice: String, AppEnum {
    case displayPort1 = "dp1", displayPort2 = "dp2", hdmi1 = "hdmi1", hdmi2 = "hdmi2", usbC = "usbc"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Monitor Input"
    static var caseDisplayRepresentations: [InputChoice: DisplayRepresentation] = [
        .displayPort1: "DisplayPort 1", .displayPort2: "DisplayPort 2", .hdmi1: "HDMI 1", .hdmi2: "HDMI 2", .usbC: "USB-C",
    ]
}

enum PiPChoice: String, AppEnum {
    // Raw values are the words `VCP.pipCode(from:)` understands; the ratio names this Mac's share first.
    case off, small, large, split, split2575 = "25/75", split7525 = "75/25"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Picture-in-Picture Mode"
    static var caseDisplayRepresentations: [PiPChoice: DisplayRepresentation] = [
        .off: "Off", .small: "Small window", .large: "Large window", .split: "Side by side",
        .split2575: "Side by side, this Mac 25%", .split7525: "Side by side, this Mac 75%",
    ]
}

struct SwitchInputIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Monitor Input"
    static var description = IntentDescription("Switches a monitor to another input over DDC/CI.")
    @Parameter(title: "Input") var input: InputChoice
    @Parameter(title: "Monitor", description: "Part of the monitor's name. Leave empty for the first monitor.") var monitor: String?
    static var parameterSummary: some ParameterSummary { Summary("Switch \(\.$monitor) to \(\.$input)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = try await Actions.shared.switchInput(input.rawValue, monitor: monitor)
        return .result(dialog: "\(r.monitor) switched to \(r.input).")
    }
}

struct SetBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Monitor Brightness"
    @Parameter(title: "Brightness", inclusiveRange: (0, 100)) var value: Int
    @Parameter(title: "Monitor") var monitor: String?
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$monitor) brightness to \(\.$value)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await Actions.shared.setBrightness(value, monitor: monitor)
        return .result(dialog: "\(name) brightness set to \(value).")
    }
}

struct SetContrastIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Monitor Contrast"
    @Parameter(title: "Contrast", inclusiveRange: (0, 100)) var value: Int
    @Parameter(title: "Monitor") var monitor: String?
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$monitor) contrast to \(\.$value)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await Actions.shared.setContrast(value, monitor: monitor)
        return .result(dialog: "\(name) contrast set to \(value).")
    }
}

struct SetPiPIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Picture-in-Picture"
    @Parameter(title: "Mode") var mode: PiPChoice
    @Parameter(title: "Monitor") var monitor: String?
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$monitor) picture-in-picture to \(\.$mode)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = try await Actions.shared.setPiP(mode.rawValue, monitor: monitor)
        return .result(dialog: "\(r.monitor) picture-in-picture: \(r.mode).")
    }
}

struct SleepMonitorIntent: AppIntent {
    static var title: LocalizedStringResource = "Put Monitor to Sleep"
    @Parameter(title: "Monitor") var monitor: String?
    static var parameterSummary: some ParameterSummary { Summary("Put \(\.$monitor) to sleep") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await Actions.shared.sleep(monitor: monitor)
        return .result(dialog: "\(name) is going to sleep.")
    }
}

struct OpenSwitcherIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Input Switcher"
    // Not `openAppWhenRun`: the app is a menu bar agent (LSUIElement) and Siri cannot "open" it the way it
    // opens a windowed app; it answered "can't open MonitorMenu because it's restricted" (O9, 2026-10-23).
    // The intent runs inside the running app, which brings its own panel forward.
    @MainActor func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        Actions.shared.openSwitcher?()
        return .result(dialog: "Switcher open.")
    }
}

// The AppShortcutsProvider (the phrases) lives in Voice.swift, the v1.5 voice-activation seam (D15).
