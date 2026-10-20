import Foundation
import CoreGraphics
import SwitchCore

/// The one action layer behind the menu, the hotkey switcher, the URL scheme and the intents (D6, D9).
/// Resolves "which monitor" the same way everywhere: by name substring, else the first one.
@MainActor
final class Actions {
    static var shared: Actions!
    private let store: MonitorStore
    var openSwitcher: (() -> Void)?

    init(store: MonitorStore) { self.store = store }

    enum ActionError: LocalizedError {
        case noMonitor(String?), unknownInput(String), ddc(String), badValue(String)
        var errorDescription: String? {
            switch self {
            case .noMonitor(let s): return s.map { "No monitor matches \"\($0)\"" } ?? "No DDC-capable monitor is connected"
            case .unknownInput(let s): return "Unknown input \"\(s)\""
            case .ddc(let s): return s
            case .badValue(let s): return "Bad value \"\(s)\""
            }
        }
    }

    func resolve(_ selector: String?) throws -> MonitorState {
        let states = store.states
        guard !states.isEmpty else { throw ActionError.noMonitor(nil) }
        guard let sel = selector?.trimmingCharacters(in: .whitespaces), !sel.isEmpty else { return states[0] }
        if let m = states.first(where: { $0.name.lowercased().contains(sel.lowercased()) || $0.id == sel || $0.displayID.map { "\($0)" == sel } == true }) { return m }
        throw ActionError.noMonitor(sel)
    }

    private func run(_ id: String, _ body: @escaping (Monitor) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.perform(on: id, body) { err in
                if let err { c.resume(throwing: ActionError.ddc(err)) } else { c.resume() }
            }
        }
    }

    @discardableResult
    func switchInput(_ text: String, monitor: String? = nil) async throws -> (monitor: String, input: String) {
        guard let code = VCP.inputCode(from: text) else { throw ActionError.unknownInput(text) }
        let s = try resolve(monitor)
        try await run(s.id) { try $0.setInput(code) }
        return (s.name, VCP.label(code: VCP.inputSource, value: code))
    }

    @discardableResult
    func setBrightness(_ value: Int, monitor: String? = nil) async throws -> String {
        let s = try resolve(monitor)
        try await run(s.id) { try $0.setBrightness(UInt16(max(0, min(100, value)))) }
        return s.name
    }

    @discardableResult
    func setContrast(_ value: Int, monitor: String? = nil) async throws -> String {
        let s = try resolve(monitor)
        try await run(s.id) { try $0.setContrast(UInt16(max(0, min(100, value)))) }
        return s.name
    }

    /// Accepts off, small, large, split, or a hex/decimal code the monitor advertises.
    @discardableResult
    func setPiP(_ text: String, monitor: String? = nil) async throws -> (monitor: String, mode: String) {
        let s = try resolve(monitor)
        guard let code = VCP.pipCode(from: text) else { throw ActionError.badValue(text) }
        try await run(s.id) { try $0.setPiPMode(code) }
        return (s.name, VCP.label(code: VCP.pipMode, value: code))
    }

    @discardableResult
    func setPiPSource(_ text: String, monitor: String? = nil) async throws -> String {
        guard let code = VCP.inputCode(from: text) else { throw ActionError.unknownInput(text) }
        let s = try resolve(monitor)
        try await run(s.id) { try $0.setPiPSource(code) }
        return s.name
    }

    @discardableResult
    func sleep(monitor: String? = nil) async throws -> String {
        let s = try resolve(monitor)
        let code: UInt8 = s.powerModes.contains(0x04) ? 0x04 : 0x05
        try await run(s.id) { try $0.setPower(code) }
        return s.name
    }

    func rescan() { store.discover() }

    /// switchbar://input/hdmi2?display=dell · brightness/60 · contrast/70 · pip/small · pip-source/hdmi1 · sleep · switcher · rescan
    func handle(url: URL) async throws -> String {
        let display = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "display" }?.value
        let verb = url.host ?? ""
        let arg = url.pathComponents.dropFirst().first ?? ""
        switch verb {
        case "input": let r = try await switchInput(arg, monitor: display); return "\(r.monitor): input → \(r.input)"
        case "brightness": guard let v = Int(arg) else { throw ActionError.badValue(arg) }; return "\(try await setBrightness(v, monitor: display)): brightness → \(v)"
        case "contrast": guard let v = Int(arg) else { throw ActionError.badValue(arg) }; return "\(try await setContrast(v, monitor: display)): contrast → \(v)"
        case "pip": let r = try await setPiP(arg, monitor: display); return "\(r.monitor): PiP → \(r.mode)"
        case "pip-source": return "\(try await setPiPSource(arg, monitor: display)): PiP source → \(arg)"
        case "sleep": return "\(try await sleep(monitor: display)): sleep"
        case "switcher": openSwitcher?(); return "switcher"
        case "rescan": rescan(); return "rescan"
        default: throw ActionError.badValue(url.absoluteString)
        }
    }
}
