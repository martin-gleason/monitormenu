import AppIntents
import SwitchCore

// FR7, FR9: App Intents make every action a Shortcuts action and, via AppShortcutsProvider,
// a Siri phrase with no setup. All call Actions.shared, the same path as the menu (D9).

enum InputChoice: String, AppEnum {
    case displayPort1 = "dp1", displayPort2 = "dp2", hdmi1 = "hdmi1", hdmi2 = "hdmi2", usbC = "usbc"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Monitor Input"
    static var caseDisplayRepresentations: [InputChoice: DisplayRepresentation] = [
        .displayPort1: "DisplayPort 1", .displayPort2: "DisplayPort 2", .hdmi1: "HDMI 1", .hdmi2: "HDMI 2", .usbC: "USB-C",
    ]
}

enum PiPChoice: String, AppEnum {
    case off, small, large, split
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Picture-in-Picture Mode"
    static var caseDisplayRepresentations: [PiPChoice: DisplayRepresentation] = [
        .off: "Off", .small: "Small window", .large: "Large window", .split: "Side by side",
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
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        Actions.shared.openSwitcher?()
        return .result()
    }
}

/// FR9: these phrases work with Siri and appear in Spotlight and the Shortcuts app on first launch.
struct SwitchBarShortcuts: AppShortcutsProvider {
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
    }
}
