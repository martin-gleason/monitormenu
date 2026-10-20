import Foundation
import CoreGraphics
import SwitchCore

/// What the menu shows for one monitor. Read on the DDC queue, published on main.
struct MonitorState {
    let monitor: Monitor
    var inputs: [UInt8] = []
    var currentInput: UInt8?
    var brightness: (current: UInt16, max: UInt16)?
    var contrast: (current: UInt16, max: UInt16)?
    var pipModes: [UInt8] = []
    var pipMode: UInt8?
    var powerModes: [UInt8] = []
    var lastError: String?
    var name: String { monitor.name }
    var id: CGDirectDisplayID { monitor.identity.displayID ?? 0 }
}

/// Owns discovery, the serial DDC work queue, and the latest state per monitor (FR1, FR8, NFR4).
/// Nothing here touches AppKit; the delegate observes `onChange`.
final class MonitorStore {
    private(set) var states: [MonitorState] = []
    var onChange: (() -> Void)?
    private let work = DispatchQueue(label: "dev.marty.SwitchBar.work", qos: .userInitiated)
    private var rediscoverPending = false
    /// Capabilities by monitor serial, kept across rediscovery so a monitor that is mid-link-renegotiation
    /// (PiP on/off and input switches both make macOS reconfigure the display) is not dropped.
    private var knownCapabilities: [String: Capabilities] = [:]
    private var emptyRetries = 0

    init() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.disabledFlag) || flags.contains(.enabledFlag), let info = userInfo else { return }
            Unmanaged<MonitorStore>.fromOpaque(info).takeUnretainedValue().scheduleRediscover()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func scheduleRediscover() {
        guard !rediscoverPending else { return }
        rediscoverPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.rediscoverPending = false
            self?.discover()
        }
    }

    /// Finds monitors and reads each one's capabilities and state. Displays without DDC are dropped (FR1, D4).
    func discover() {
        work.async { [weak self] in
            guard let self else { return }
            var found: [MonitorState] = []
            let discovered = MonitorDiscovery.discover()
            for m in discovered {
                var s = MonitorState(monitor: m)
                let key = m.identity.alphanumericSerial ?? "\(m.identity.vendor)-\(m.identity.model)-\(m.identity.serial)"
                do {
                    let caps = try m.loadCapabilities()
                    DispatchQueue.main.async { self.knownCapabilities[key] = caps }
                } catch {
                    s.lastError = "\(error)"
                    // Not answering right now. Keep it if we have ever read its capabilities; otherwise it is not a DDC monitor.
                    if let caps = DispatchQueue.main.sync(execute: { self.knownCapabilities[key] }) { m.adopt(capabilities: caps) } else { continue }
                }
                s.inputs = m.inputs(); s.pipModes = m.pipModes(); s.powerModes = m.powerModes()
                self.readValues(into: &s)
                found.append(s)
            }
            DispatchQueue.main.async {
                self.states = found; self.onChange?()
                // A display came and went during a link renegotiation: look again shortly, a few times.
                if found.isEmpty, !discovered.isEmpty || self.emptyRetries < 3 {
                    self.emptyRetries += 1
                    if self.emptyRetries <= 3 { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.discover() } }
                } else { self.emptyRetries = 0 }
            }
        }
    }

    /// Re-reads live values for every monitor (menu open, after an action) — FR8.
    func refresh(only id: CGDirectDisplayID? = nil) {
        work.async { [weak self] in
            guard let self else { return }
            var updated = self.states
            for i in updated.indices where id == nil || updated[i].id == id {
                self.readValues(into: &updated[i])
            }
            DispatchQueue.main.async { self.states = updated; self.onChange?() }
        }
    }

    private func readValues(into s: inout MonitorState) {
        let m = s.monitor
        s.lastError = nil
        if m.capabilities == nil, let caps = try? m.loadCapabilities() {
            s.inputs = m.inputs(); s.pipModes = m.pipModes(); s.powerModes = m.powerModes(); _ = caps
        }
        do {
            s.currentInput = try m.currentInput()
            s.brightness = try m.brightness()
            s.contrast = try m.contrast()
            if m.hasPiP { s.pipMode = UInt8((try m.get(VCP.pipMode)).current & 0xFF) }
        } catch { s.lastError = "\(error)" }
    }

    /// Every action funnels through here: write on the queue, then re-read that monitor (FR8).
    func perform(on id: CGDirectDisplayID, _ action: @escaping (Monitor) throws -> Void, completion: ((String?) -> Void)? = nil) {
        guard let s = states.first(where: { $0.id == id }) else { completion?("monitor is gone"); return }
        work.async { [weak self] in
            var err: String?
            do { try action(s.monitor) } catch { err = "\(error)" }
            DispatchQueue.main.async { completion?(err) }
            self?.refresh(only: id)
        }
    }
}
