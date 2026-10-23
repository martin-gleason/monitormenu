import Foundation

/// FR10: names the user gives monitors. Keyed by the monitor's serial (`MonitorIdentity.key`), never
/// by its CoreGraphics id, which changes on every link retrain (M7). Stored in the app's defaults suite,
/// which `monitorctl` shares, so a rename from either side is seen by the other on the next read.
public final class MonitorNames {
    public static let suiteName = "dev.marty.MonitorMenu"
    static let key = "monitorNames"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: MonitorNames.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    public var all: [String: String] { defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:] }

    /// The user's name for this monitor, or nil when it has none.
    public func name(for identity: MonitorIdentity) -> String? {
        let n = all[identity.key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n?.isEmpty ?? true) ? nil : n
    }

    /// The name to show: the user's, else the monitor's own.
    public func displayName(for identity: MonitorIdentity) -> String { name(for: identity) ?? identity.name }

    /// Empty or whitespace clears the name.
    public func set(_ name: String?, for identity: MonitorIdentity) {
        var d = all
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { d.removeValue(forKey: identity.key) } else { d[identity.key] = String(trimmed.prefix(64)) }
        defaults.set(d, forKey: Self.key)
    }

    public func clear(for identity: MonitorIdentity) { set(nil, for: identity) }

    /// One resolver for the menu, the switcher, intents, URLs and the CLI. Tiers, each tried in turn and
    /// each refusing to guess: exact user name, exact serial key, exact CoreGraphics id, exact monitor
    /// name, then a case-insensitive substring of the user name, then of the monitor name. The first tier
    /// with exactly one hit wins; a tier with more than one hit is ambiguous and throws, so discovery
    /// order never decides and a user name can never shadow a serial (review F2 #1). An empty selector is
    /// the first monitor, which the intents document as the default.
    public func match(_ selector: String, in identities: [MonitorIdentity]) throws -> MonitorIdentity? {
        let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty else { return identities.first }
        let low = sel.lowercased()
        let tiers: [(MonitorIdentity) -> Bool] = [
            { self.name(for: $0)?.lowercased() == low },
            { $0.key == sel },
            { $0.displayID.map { "\($0)" == sel } == true },
            { $0.name.lowercased() == low },
            { self.name(for: $0)?.lowercased().contains(low) ?? false },
            { $0.name.lowercased().contains(low) },
        ]
        for tier in tiers {
            let hits = identities.filter(tier)
            if hits.count == 1 { return hits[0] }
            if hits.count > 1 { throw DDCError.ambiguousMonitor(sel, hits.map { displayName(for: $0) + " [\($0.key)]" }) }
        }
        return nil
    }
}
