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
        // Any completed reconfiguration — a PiP or input change is a mode change, not an add or remove —
        // can replace the display's IOAVService, so every "after" event triggers a (debounced) rediscovery.
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let info = userInfo else { return }
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
            let found = self.discoverSync()
            DispatchQueue.main.async {
                self.states = found; self.onChange?()
                // A display came and went during a link renegotiation: look again shortly, a few times.
                if found.isEmpty, self.emptyRetries < 3 {
                    self.emptyRetries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.discover() }
                } else { self.emptyRetries = 0 }
            }
        }
    }

    /// Runs on the work queue. Main must never block on the work queue (it does not: every DDC call is
    /// dispatched asynchronously from main), or the one `main.sync` hop here would deadlock.
    private func discoverSync() -> [MonitorState] {
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
            _ = discovered
            return found
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
                guard let self else { return }
                var err: String?
                do { try action(monitor) } catch let first {
                    if case DDCError.ioFailed = first {
                        // The display reconfigured under us and the IOAVService is stale (MACH_SEND_INVALID_DEST):
                        // rediscover inline and retry once on the fresh service.
                        let fresh = self.discoverSync()
                        DispatchQueue.main.async { self.states = fresh; self.onChange?() }
                        if let again = fresh.first(where: { $0.id == id })?.monitor {
                            do { try action(again) } catch { err = "\(error)" }
                        } else { err = "\(first)" }
                    } else { err = "\(first)" }
                }
                DispatchQueue.main.async { completion?(err) }
                self.refresh(only: id)
            }
        }
    }
}
