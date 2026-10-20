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
            // Note: main must never block on the work queue, or the `main.sync` below deadlocks. It does not: all
            // DDC work is dispatched asynchronously from main.
            var found: [MonitorState] = []
            let known = DispatchQueue.main.sync { self.knownCapabilities }   // one hop, before any DDC work
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
                    if let caps = known[key] { m.adopt(capabilities: caps) } else { continue }
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
    /// `states` belongs to the main thread: snapshot there, work on the copy, publish back on main.
    func refresh(only id: CGDirectDisplayID? = nil) {
        onMain { [weak self] in
            guard let self else { return }
            let snapshot = self.states
            self.work.async { [weak self] in
                guard let self else { return }
                var updated = snapshot
                for i in updated.indices where id == nil || updated[i].id == id {
                    self.readValues(into: &updated[i])
                }
                DispatchQueue.main.async {
                    // Merge by id, and only onto the same Monitor object: a discovery that landed meanwhile
                    // holds a fresh IOAVService, and the snapshot's stale one would fail with MACH_SEND_INVALID_DEST.
                    for u in updated {
                        if let k = self.states.firstIndex(where: { $0.id == u.id }), self.states[k].monitor === u.monitor { self.states[k] = u }
                    }
                    self.onChange?()
                }
            }
        }
    }

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    private func readValues(into s: inout MonitorState) {
        let m = s.monitor
        s.lastError = nil
        if m.capabilities == nil, (try? m.loadCapabilities()) != nil {
            s.inputs = m.inputs(); s.pipModes = m.pipModes(); s.powerModes = m.powerModes()
        }
        do {
            s.currentInput = try m.currentInput()
            s.brightness = try m.brightness()
            s.contrast = try m.contrast()
            if m.hasPiP { s.pipMode = try m.currentPiPMode() }
        } catch { s.lastError = "\(error)" }
    }

    /// Every action funnels through here: write on the queue, then re-read that monitor (FR8).
    func perform(on id: CGDirectDisplayID, _ action: @escaping (Monitor) throws -> Void, completion: ((String?) -> Void)? = nil) {
        onMain { [weak self] in
            guard let self else { return }
            guard let s = self.states.first(where: { $0.id == id }) else { completion?("monitor is gone"); return }
            let monitor = s.monitor
            self.work.async { [weak self] in
                var err: String?
                do { try action(monitor) } catch { err = "\(error)" }
                DispatchQueue.main.async {
                    completion?(err)
                    // A failed transport call usually means the display just reconfigured: look again.
                    if err != nil { self?.scheduleRediscover() }
                }
                self?.refresh(only: id)
            }
        }
    }
}
