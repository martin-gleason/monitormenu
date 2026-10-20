import Foundation
import CDDC

/// One monitor's DDC/CI byte channel. The only thing the protocol layer needs from the OS.
/// `IOAVServiceChannel` is the Apple silicon implementation; tests use `RecordingChannel`.
public protocol I2CChannel: AnyObject {
    /// Writes one DDC frame (the bytes after the 0x51 sub-address).
    func write(_ bytes: [UInt8]) throws
    /// Reads `count` bytes of reply, starting at the destination-address byte.
    func read(count: Int) throws -> [UInt8]
}

public enum DDCError: Error, Equatable, CustomStringConvertible {
    case ioFailed(String, Int32)
    case timeout(String)
    case badReply(String)
    case notAdvertised(code: UInt8)
    case valueNotAdvertised(code: UInt8, value: UInt16)
    case refusedFactoryReset(code: UInt8)
    case noSuchMonitor(String)

    public var description: String {
        switch self {
        case .ioFailed(let what, let rc): return "\(what) failed (IOReturn \(rc))"
        case .timeout(let what): return "\(what) timed out"
        case .badReply(let why): return "bad reply: \(why)"
        case .notAdvertised(let c): return String(format: "VCP 0x%02X is not advertised by this monitor", c)
        case .valueNotAdvertised(let c, let v): return String(format: "value 0x%02X is not advertised for VCP 0x%02X", v, c)
        case .refusedFactoryReset(let c): return String(format: "VCP 0x%02X is a factory reset and is never sent", c)
        case .noSuchMonitor(let s): return "no monitor matches \"\(s)\""
        }
    }
}

/// DDC/CI over IOKit's IOAVService I2C bridge (D1). Chip address 0x37, sub-address 0x51.
public final class IOAVServiceChannel: I2CChannel {
    private let service: IOAVService
    private static let chip: UInt32 = 0x37
    private static let sub: UInt32 = 0x51

    init(service: IOAVService) { self.service = service }

    public func write(_ bytes: [UInt8]) throws {
        var buf = bytes
        let rc = buf.withUnsafeMutableBytes { raw in
            IOAVServiceWriteI2C(service, Self.chip, Self.sub, raw.baseAddress, UInt32(raw.count))
        }
        if rc != KERN_SUCCESS { throw DDCError.ioFailed("I2C write", rc) }
    }

    public func read(count: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        let rc = buf.withUnsafeMutableBytes { raw in
            IOAVServiceReadI2C(service, Self.chip, Self.sub, raw.baseAddress, UInt32(raw.count))
        }
        if rc != KERN_SUCCESS { throw DDCError.ioFailed("I2C read", rc) }
        return buf
    }
}

/// Test double: records every write, replays scripted reads.
public final class RecordingChannel: I2CChannel {
    public private(set) var writes: [[UInt8]] = []
    public var replies: [[UInt8]] = []
    public init() {}
    public func write(_ bytes: [UInt8]) throws { writes.append(bytes) }
    public func read(count: Int) throws -> [UInt8] {
        guard !replies.isEmpty else { throw DDCError.badReply("no scripted reply") }
        let r = replies.removeFirst()
        return r.count >= count ? Array(r.prefix(count)) : r + [UInt8](repeating: 0, count: count - r.count)
    }
}
