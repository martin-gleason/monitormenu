import Foundation
import CoreGraphics
import MonitorCore

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
    /// Identity key for actions and menu items: the serial, which survives the display-id changes PiP causes.
    var id: String { monitor.identity.key }
    var displayID: CGDirectDisplayID? { monitor.identity.displayID }
}

/// Owns discovery, the serial DDC work queue, and the latest state per monitor (FR1, FR8, NFR4).
/// Nothing here touches AppKit; the delegate observes `onChange`.
final class MonitorStore {
    private(set) var states: [MonitorState] = []
    var onChange: (() -> Void)?
    private let work = DispatchQueue(label: "dev.marty.MonitorMenu.work", qos: .userInitiated)
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
            NSLog("MonitorMenu: display reconfigured (flags 0x%x)", flags.rawValue)
            Unmanaged<MonitorStore>.fromOpaque(info).takeUnretainedValue().scheduleRediscover()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Kicks a discovery unless one is already scheduled; used when an action finds the list empty.
    func rescanIfIdle() { if !rediscoverPending { discover() } }

    func scheduleRediscover() {
        guard !rediscoverPending else { return }
        NSLog("MonitorMenu: screen change — rediscovery scheduled")
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
                // A display came and went during a link renegotiation, or CoreGraphics had not paired it yet:
                // look again shortly, a few times.
                if found.isEmpty || found.contains(where: { $0.displayID == nil }), self.emptyRetries < 3 {
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
                let key = m.identity.key
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
            NSLog("MonitorMenu: discovery → %@", found.map { "\($0.name) [\($0.id)] display \($0.displayID.map(String.init) ?? "?")\($0.lastError.map { " (" + $0 + ")" } ?? "")" }.joined(separator: ", "))
            return found
    }

    /// Re-reads live values for every monitor (menu open, after an action) — FR8.
    /// `states` belongs to the main thread: snapshot there, work on the copy, publish back on main.
    func refresh(only id: String? = nil) {
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
    /// `retrainsLink`: input and PiP changes make the G3223D retrain its link a few seconds later, which
    /// replaces its IOAVService; a rediscovery is scheduled so the next action does not pay for it.
    func perform(on id: String, retrainsLink: Bool = false, _ action: @escaping (Monitor) throws -> Void, completion: ((String?) -> Void)? = nil) {
        onMain { [weak self] in
            guard let self else { return }
            guard let s = self.states.first(where: { $0.id == id }) else { completion?("monitor is gone"); return }
            let monitor = s.monitor
            self.work.async { [weak self] in
                guard let self else { return }
                var err: String?
                do { try action(monitor) } catch let first {
                    NSLog("MonitorMenu: action on %@ failed: %@", id, "\(first)")
                    err = "\(first)"
                    if case DDCError.ioFailed = first {
                        // The display retrained its link and the IOAVService is gone (MACH_SEND_INVALID_DEST). The
                        // monitor can be absent from the registry for a second or two: rediscover and retry, up to
                        // three rounds a second apart.
                        for round in 1...3 {
                            Thread.sleep(forTimeInterval: round == 1 ? 0.3 : 1.0)
                            let fresh = self.discoverSync()
                            if !fresh.isEmpty { DispatchQueue.main.async { self.states = fresh; self.onChange?() } }
                            guard let again = fresh.first(where: { $0.id == id })?.monitor else { continue }
                            do { try action(again); err = nil; NSLog("MonitorMenu: retry %d on fresh service succeeded", round); break }
                            catch { err = "retry \(round): \(error)"; if case DDCError.ioFailed = error { continue } else { break } }
                        }
                    }
                }
                DispatchQueue.main.async {
                    completion?(err)
                    if retrainsLink, err == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.discover() } }
                }
                self.refresh(only: id)
            }
        }
    }
}
