// Created: 2026-10-27 09:26 -05:00 · Edited: 2026-10-27 09:26 -05:00
import Foundation

/// The monitor's capabilities string, remembered per monitor so it is read once, not once per process.
///
/// Reading it costs 14 round trips, about 2.3 s on the G3223D, and before this cache every `monitorctl`
/// call and every app launch paid it (C4-T1: `monitorctl get brightness` took 2.8 s, of which 0.06 s
/// was everything else). Keyed by `MonitorIdentity.key` (the serial, M12), kept in the defaults suite the
/// app and the CLI share. The whitelist is still the monitor's own string (NFR5, D3): it came from the
/// same serial. A string that no longer parses is ignored and read again. A monitor whose firmware
/// changed its string is re-read by Rescan Displays, `monitorctl capabilities`, or `--fresh`.
public final class CapabilitiesCache {
    static let key = "capabilitiesCache"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: MonitorNames.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    private var all: [String: String] { defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:] }

    /// The remembered string for this monitor, or nil when there is none or it does not parse to any VCP code.
    public func raw(for identity: MonitorIdentity) -> String? {
        guard let raw = all[identity.key], !Capabilities.parse(raw).vcp.isEmpty else { return nil }
        return raw
    }

    public func store(_ raw: String, for identity: MonitorIdentity) {
        var d = all; d[identity.key] = raw
        defaults.set(d, forKey: Self.key)
    }

    public func forget(_ identity: MonitorIdentity) {
        var d = all; d.removeValue(forKey: identity.key)
        defaults.set(d, forKey: Self.key)
    }
}
