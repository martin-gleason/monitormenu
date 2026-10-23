import Foundation
import CoreGraphics
import MonitorCore

/// The one action layer behind the menu, the hotkey switcher, the URL scheme and the intents (D6, D9).
/// Resolves "which monitor" the same way everywhere: by name substring, else the first one.
@MainActor
final class Actions {
    static var shared: Actions!
    private let store: MonitorStore
    var openSwitcher: (() -> Void)?

    init(store: MonitorStore) { self.store = store }

    enum ActionError: LocalizedError {
        case noMonitor(String?), ambiguous(String), unknownInput(String), ddc(String), badValue(String)
        var errorDescription: String? {
            switch self {
            case .noMonitor(let s): return s.map { "No monitor matches \"\($0)\"" } ?? "No DDC-capable monitor is connected"
            case .ambiguous(let s): return s
            case .unknownInput(let s): return "Unknown input \"\(s)\""
            case .ddc(let s): return s
            case .badValue(let s): return "Bad value \"\(s)\""
            }
        }
    }

    /// Picks a monitor. If none is listed right now (a link retrain empties the list for a few seconds),
    /// waits up to eight seconds for discovery before giving up.
    func resolve(_ selector: String?) async throws -> MonitorState {
        var states = store.states
        if states.isEmpty {
            store.rescanIfIdle()
            for _ in 0..<16 where states.isEmpty {
                try await Task.sleep(nanoseconds: 500_000_000)
                states = store.states
            }
        }
        guard !states.isEmpty else { throw ActionError.noMonitor(nil) }
        let sel = selector?.trimmingCharacters(in: .whitespaces) ?? ""
        // FR10: the user's name wins, then the monitor's own name, serial or display id (MonitorNames.match).
        do {
            if let id = try store.names.match(sel, in: states.map { $0.identity }), let m = states.first(where: { $0.id == id.key }) { return m }
        } catch let e as DDCError { throw ActionError.ambiguous(e.description) }
        throw ActionError.noMonitor(sel)
    }

    private func run(_ id: String, retrainsLink: Bool = false, _ body: @escaping (Monitor) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.perform(on: id, retrainsLink: retrainsLink, body) { err in
                if let err { c.resume(throwing: ActionError.ddc(err)) } else { c.resume() }
            }
        }
    }

    @discardableResult
    func switchInput(_ text: String, monitor: String? = nil) async throws -> (monitor: String, input: String) {
        guard let code = VCP.inputCode(from: text) else { throw ActionError.unknownInput(text) }
        let s = try await resolve(monitor)
        try await run(s.id, retrainsLink: true) { try $0.setInput(code) }
        return (store.names.displayName(for: s.identity), VCP.label(code: VCP.inputSource, value: code))
    }

    @discardableResult
    func setBrightness(_ value: Int, monitor: String? = nil) async throws -> String {
        let s = try await resolve(monitor)
        try await run(s.id) { try $0.setBrightness(UInt16(max(0, min(100, value)))) }
        return store.names.displayName(for: s.identity)
    }

    @discardableResult
    func setContrast(_ value: Int, monitor: String? = nil) async throws -> String {
        let s = try await resolve(monitor)
        try await run(s.id) { try $0.setContrast(UInt16(max(0, min(100, value)))) }
        return store.names.displayName(for: s.identity)
    }

    /// Accepts off, small, large, split, or a hex/decimal code the monitor advertises.
    @discardableResult
    func setPiP(_ text: String, monitor: String? = nil) async throws -> (monitor: String, mode: String) {
        let s = try await resolve(monitor)
        guard let code = VCP.pipCode(from: text) else { throw ActionError.badValue(text) }
        try await run(s.id, retrainsLink: true) { try $0.setPiPMode(code) }
        return (store.names.displayName(for: s.identity), VCP.label(code: VCP.pipMode, value: code))
    }

    @discardableResult
    func setPiPSource(_ text: String, monitor: String? = nil) async throws -> String {
        guard let code = VCP.inputCode(from: text) else { throw ActionError.unknownInput(text) }
        let s = try await resolve(monitor)
        try await run(s.id) { try $0.setPiPSource(code) }
        return store.names.displayName(for: s.identity)
    }

    @discardableResult
    func sleep(monitor: String? = nil) async throws -> String {
        let s = try await resolve(monitor)
        let code: UInt8 = s.powerModes.contains(0x04) ? 0x04 : 0x05
        try await run(s.id) { try $0.setPower(code) }
        return store.names.displayName(for: s.identity)
    }

    func rescan() { store.discover() }

    /// monitormenu://input/hdmi2?display=dell · brightness/60 · contrast/70 · pip/small · pip-source/hdmi1 · sleep · switcher · rescan · rename/Desk?display=dell
    func handle(url: URL) async throws -> String {
        let display = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "display" }?.value
        let verb = url.host ?? ""
        let arg = url.pathComponents.dropFirst().first ?? ""
        switch verb {
        case "input": let r = try await switchInput(arg, monitor: display); return "\(r.monitor): input → \(r.input)"
        case "rename":
            // The whole path is the name (so "Left/Right" survives); URL.path is already percent-decoded once.
            // An empty name is refused here: clearing is `monitormenu://rename/-` or the menu, never a typo (review F2 #2, #4).
            let s = try await resolve(display)
            let newName = String(url.path.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { throw ActionError.badValue("rename needs a name; use rename/- to clear") }
            store.names.set(newName == "-" ? nil : newName, for: s.identity)
            store.onChange?()
            return "\(s.name): \(newName == "-" ? "name cleared" : "named \"\(store.names.displayName(for: s.identity))\"")"
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
