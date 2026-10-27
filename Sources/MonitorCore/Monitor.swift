import Foundation
import CoreGraphics

/// Identity read from the IORegistry display node and matched to a CoreGraphics display.
public struct MonitorIdentity: Equatable, Codable {
    public var name: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var alphanumericSerial: String?
    public var displayID: CGDirectDisplayID?
    /// Stable across reconfigurations, unlike `displayID`: the serial, else vendor-model-serial.
    public var key: String { alphanumericSerial.flatMap { $0.isEmpty ? nil : $0 } ?? "\(vendor)-\(model)-\(serial)" }

    public init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, alphanumericSerial: String? = nil, displayID: CGDirectDisplayID? = nil) {
        self.name = name; self.vendor = vendor; self.model = model; self.serial = serial
        self.alphanumericSerial = alphanumericSerial; self.displayID = displayID
    }
}

/// One external monitor with a DDC channel and the whitelist read from it.
public final class Monitor {
    public let identity: MonitorIdentity
    public let link: DDCMonitorLink
    public private(set) var capabilities: Capabilities?
    /// Maximum values the monitor reported for continuous codes, used to bound writes (review C8).
    private var maxima: [UInt8: UInt16] = [:]
    /// What the last `pictureLock()` read said: the preset's label while brightness and contrast are locked (D14).
    private var lockedByValue: String?
    private let lock = NSLock()

    public init(identity: MonitorIdentity, link: DDCMonitorLink, capabilities: Capabilities? = nil) {
        self.identity = identity; self.link = link; self.capabilities = capabilities
    }

    public var name: String { identity.name }

    /// Reads the capabilities string from the monitor. Required before any write (D3).
    @discardableResult
    public func loadCapabilities() throws -> Capabilities {
        let caps = Capabilities.parse(try link.capabilitiesString())
        capabilities = caps
        return caps
    }

    /// Reuses capabilities read earlier from the same monitor (same serial) when it is not answering right now.
    public func adopt(capabilities caps: Capabilities) { capabilities = caps }

    public func get(_ code: UInt8) throws -> DDCFrame.VCPReply {
        let r = try link.read(code)
        if r.supported, r.maximum > 0 { lock.lock(); maxima[code] = r.maximum; lock.unlock() }
        return r
    }

    /// The preset label while the monitor is ignoring brightness and contrast, as of the last `pictureLock()` read.
    public var lockedBy: String? { lock.lock(); defer { lock.unlock() }; return lockedByValue }

    /// Reads the vendor's locking preset (D14): nil when this vendor has none, when the monitor does not
    /// advertise the code (no I2C at all, NFR8), or when the value is not a locking one. The answer is
    /// remembered, so `set` can refuse without a read of its own (M11).
    @discardableResult
    public func pictureLock() throws -> String? {
        guard let p = VCP.lockingPreset(vendor: identity.vendor), capabilities?.advertises(p.code) == true else { return nil }
        let value = UInt8(try get(p.code).current & 0xFF)
        let by = p.values.contains(value) ? p.label : nil
        lock.lock(); lockedByValue = by; lock.unlock()
        return by
    }

    /// The only write path. Refuses anything the monitor did not advertise (NFR5, M1, M4), and a locked
    /// code while the monitor's preset is ignoring it (D14, M11).
    public func set(_ code: UInt8, _ value: UInt16) throws {
        if VCP.factoryResets.contains(code) { throw DDCError.refusedFactoryReset(code: code) }
        guard let caps = capabilities, caps.advertises(code) else { throw DDCError.notAdvertised(code: code) }
        if VCP.lockedCodes.contains(code), let by = lockedBy { throw DDCError.locked(code: code, by: by) }
        if let allowed = caps.values(for: code), !allowed.isEmpty {
            guard value <= 0xFF, allowed.contains(UInt8(value)) else { throw DDCError.valueNotAdvertised(code: code, value: value) }
        } else {
            // A continuous code is never written before its range is known (A2-3, M9): read it once, then bound.
            lock.lock(); var max = maxima[code]; lock.unlock()
            if max == nil { max = try get(code).maximum }
            if let max, max > 0, value > max { throw DDCError.valueNotAdvertised(code: code, value: value) }
        }
        try link.writeUnchecked(code, value)
    }

    // Convenience, all funnelled through `set`.
    public func inputs() -> [UInt8] { capabilities?.values(for: VCP.inputSource) ?? [] }
    public func currentInput() throws -> UInt8 { UInt8(try get(VCP.inputSource).current & 0xFF) }
    public func setInput(_ code: UInt8) throws { try set(VCP.inputSource, UInt16(code)) }
    public func brightness() throws -> (current: UInt16, max: UInt16) { let r = try get(VCP.brightness); return (r.current, r.maximum) }
    public func setBrightness(_ v: UInt16) throws { try set(VCP.brightness, v) }
    public func contrast() throws -> (current: UInt16, max: UInt16) { let r = try get(VCP.contrast); return (r.current, r.maximum) }
    public func setContrast(_ v: UInt16) throws { try set(VCP.contrast, v) }
    public func powerModes() -> [UInt8] { capabilities?.values(for: VCP.powerMode) ?? [] }
    public func setPower(_ v: UInt8) throws { try set(VCP.powerMode, UInt16(v)) }
    /// PiP codes for this monitor's manufacturer, if known and advertised (FR4, NFR8).
    public var pipCodes: (mode: UInt8, source: UInt8)? {
        guard let c = VCP.pipCodes(vendor: identity.vendor), capabilities?.advertises(c.mode) == true else { return nil }
        return c
    }
    public var hasPiP: Bool { pipCodes != nil }
    public var hasPiPSource: Bool { pipCodes.map { capabilities?.advertises($0.source) == true } ?? false }
    public func pipModes() -> [UInt8] { pipCodes.flatMap { capabilities?.values(for: $0.mode) } ?? [] }
    public func currentPiPMode() throws -> UInt8 {
        guard let c = pipCodes else { throw DDCError.notAdvertised(code: VCP.pipMode) }
        return UInt8(try get(c.mode).current & 0xFF)
    }
    public func setPiPMode(_ v: UInt8) throws {
        guard let c = pipCodes else { throw DDCError.notAdvertised(code: VCP.pipMode) }
        try set(c.mode, UInt16(v))
    }
    public func setPiPSource(_ input: UInt8) throws {
        guard let c = pipCodes else { throw DDCError.notAdvertised(code: VCP.pipSource) }
        try set(c.source, UInt16(input))
    }
}
