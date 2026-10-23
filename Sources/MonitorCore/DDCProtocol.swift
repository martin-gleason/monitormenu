import Foundation

/// Pure DDC/CI framing (MCCS 2.x). No I/O here, so every byte is testable (M3, M5).
public enum DDCFrame {
    static let hostAddress: UInt8 = 0x6E   // 0x37 << 1, the monitor as seen by the host
    static let hostSource: UInt8 = 0x51     // sub-address the host writes from
    static let replySource: UInt8 = 0x50    // seed of the checksum the monitor puts on its replies

    /// Checksum over the virtual host address, the sub-address and the frame body.
    static func checksum(_ body: [UInt8]) -> UInt8 {
        body.reduce(hostAddress ^ hostSource) { $0 ^ $1 }
    }

    /// Frame = [0x80 | len, payload..., checksum]. The 0x51 sub-address is sent by the channel.
    static func frame(_ payload: [UInt8]) -> [UInt8] {
        let body = [0x80 | UInt8(payload.count)] + payload
        return body + [checksum(body)]
    }

    public static func getVCP(_ code: UInt8) -> [UInt8] { frame([0x01, code]) }
    public static func setVCP(_ code: UInt8, _ value: UInt16) -> [UInt8] {
        frame([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }
    public static func capabilitiesRequest(offset: UInt16) -> [UInt8] {
        frame([0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
    }

    /// A reply is [0x6E, 0x80|len, body..., chk] with chk = 0x50 ^ every preceding byte.
    /// Verified on bytes the G3223D sent: `6E 88 02 00 62 00 00 64 00 51 E3`.
    public static func replyChecksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(replySource) { $0 ^ $1 }
    }

    /// Returns the checked reply (address, length, body, checksum) or throws (M5).
    static func validated(_ r: [UInt8]) throws -> ArraySlice<UInt8> {
        guard r.count >= 3 else { throw DDCError.badReply("short reply (\(r.count) bytes)") }
        guard r[0] == hostAddress else { throw DDCError.badReply(String(format: "reply address 0x%02X", r[0])) }
        let len = Int(r[1] & 0x7F)
        if len == 0 { throw DDCError.badReply("null message — monitor has no reply ready") }
        let total = 2 + len + 1
        guard r.count >= total else { throw DDCError.badReply("reply says \(len) bytes, got \(r.count - 3)") }
        guard replyChecksum(r[0..<(total - 1)]) == r[total - 1] else { throw DDCError.badReply("checksum mismatch") }
        return r[0..<total]
    }

    public struct VCPReply: Equatable {
        public let code: UInt8
        public let current: UInt16
        public let maximum: UInt16
        public let supported: Bool
    }

    /// Reply = [0x6E, 0x88, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, chk].
    /// The current value is the low word at 8–9; the input code is its low byte (M3).
    public static func parseVCPReply(_ r: [UInt8], expecting code: UInt8) throws -> VCPReply {
        let v = try validated(r)
        guard v.count == 11 else { throw DDCError.badReply("VCP reply of \(v.count) bytes") }
        guard v[2] == 0x02 else { throw DDCError.badReply(String(format: "opcode 0x%02X, expected 0x02", v[2])) }
        guard v[4] == code else { throw DDCError.badReply(String(format: "reply for 0x%02X, asked 0x%02X", v[4], code)) }
        let supported = v[3] == 0x00
        // MCCS result 0x01: the monitor says it does not support this code. Its value bytes are noise (A2-6).
        guard supported else { throw DDCError.badReply(String(format: "monitor reports VCP 0x%02X unsupported (result 0x%02X)", code, v[3])) }
        let maximum = UInt16(v[6]) << 8 | UInt16(v[7])
        let current = UInt16(v[8]) << 8 | UInt16(v[9])
        return VCPReply(code: code, current: current, maximum: maximum, supported: supported)
    }

    /// Reply = [0x6E, 0x80|len, 0xE3, offHi, offLo, fragment..., chk]. Empty fragment ends the string.
    public static func parseCapabilitiesReply(_ r: [UInt8], expectingOffset off: UInt16) throws -> [UInt8] {
        let v = try validated(r)
        guard v[2] == 0xE3 else { throw DDCError.badReply(String(format: "opcode 0x%02X, expected 0xE3", v[2])) }
        guard v.count >= 6 else { throw DDCError.badReply("capabilities reply of \(v.count) bytes") }
        let got = UInt16(v[3]) << 8 | UInt16(v[4])
        guard got == off else { throw DDCError.badReply("capabilities offset \(got), asked \(off)") }
        return Array(v[5..<(v.count - 1)])
    }
}

/// Timing from the DDC/CI spec: 40 ms minimum between a request and its reply, 50 ms between commands.
public struct DDCTiming {
    public var replyDelay: TimeInterval = 0.05
    public var commandGap: TimeInterval = 0.05
    /// Five tries with a doubling pause: a monitor renegotiating its link after a PiP or input change
    /// answers with null messages for up to a second (observed on the G3223D, 2026-10-19).
    public var attempts = 5
    public init() {}

    /// Debug knobs, read once: MONITORMENU_DEBUG dumps reply bytes; MONITORMENU_REPLY_DELAY_MS / MONITORMENU_GAP_MS tune pacing.
    static let env = ProcessInfo.processInfo.environment
    static let debug = env["MONITORMENU_DEBUG"] != nil
}

/// One monitor's DDC conversation, serialized on its own queue. Callers run these off the main
/// thread (the app's work queue); the transport underneath has its own deadline (NFR4).
public final class DDCMonitorLink {
    let channel: I2CChannel
    public var timing = DDCTiming()
    private let queue: DispatchQueue
    private var lastCommand = Date.distantPast

    public init(channel: I2CChannel, label: String) {
        self.channel = channel
        self.queue = DispatchQueue(label: "dev.marty.MonitorMenu.ddc.\(label)")
        if let ms = Double(DDCTiming.env["MONITORMENU_REPLY_DELAY_MS"] ?? "") { timing.replyDelay = ms / 1000 }
        if let ms = Double(DDCTiming.env["MONITORMENU_GAP_MS"] ?? "") { timing.commandGap = ms / 1000 }
    }

    private func pace() {
        let since = Date().timeIntervalSince(lastCommand)
        if since < timing.commandGap { Thread.sleep(forTimeInterval: timing.commandGap - since) }
    }

    /// MACH_SEND_INVALID_DEST: the IOAVService behind this link is gone (the display retrained its link,
    /// which the G3223D does on every PiP change). Retrying the same handle can never succeed.
    public static let serviceGone: Int32 = 0x1000_0003

    private func attempt<T>(_ what: String, _ body: () throws -> T) throws -> T {
        var last: Error = DDCError.timeout(what)
        var backoff = timing.commandGap
        for _ in 0..<max(1, timing.attempts) {
            pace()
            defer { lastCommand = Date() }
            do { return try body() } catch {
                if case DDCError.ioFailed(_, let rc) = error, rc == Self.serviceGone { throw error }   // fail fast; caller rediscovers
                if case DDCError.timeout = error { throw error }   // a hung transport is a rediscovery case; a retry would stack calls on the bus (A2-1, M8)
                last = error; Thread.sleep(forTimeInterval: backoff); backoff = min(backoff * 2, 1.0)
            }
        }
        throw last
    }

    public func read(_ code: UInt8) throws -> DDCFrame.VCPReply {
        try queue.sync {
            try attempt(String(format: "get VCP 0x%02X", code)) {
                try channel.write(DDCFrame.getVCP(code))
                Thread.sleep(forTimeInterval: timing.replyDelay)
                let reply = try channel.read(count: 11)
                if DDCTiming.debug {
                    FileHandle.standardError.write(Data((String(format: "ddc get 0x%02X ← ", code) + reply.map { String(format: "%02X", $0) }.joined(separator: " ") + "\n").utf8))
                }
                return try DDCFrame.parseVCPReply(reply, expecting: code)
            }
        }
    }

    /// Unchecked write. Callers go through `Monitor.set`, which enforces the whitelist (D3).
    func writeUnchecked(_ code: UInt8, _ value: UInt16) throws {
        try queue.sync {
            try attempt(String(format: "set VCP 0x%02X", code)) {
                try channel.write(DDCFrame.setVCP(code, value))
            }
        }
    }

    public func capabilitiesString() throws -> String {
        try queue.sync {
            var out: [UInt8] = []
            var offset: UInt16 = 0
            while true {
                let frag: [UInt8] = try attempt("capabilities at \(offset)") {
                    try channel.write(DDCFrame.capabilitiesRequest(offset: offset))
                    Thread.sleep(forTimeInterval: timing.replyDelay)
                    return try DDCFrame.parseCapabilitiesReply(try channel.read(count: 38), expectingOffset: offset)
                }
                if frag.isEmpty { break }
                out += frag
                offset += UInt16(frag.count)
                if out.count > 4096 { throw DDCError.badReply("capabilities string over 4 KB") }
            }
            return String(decoding: out, as: UTF8.self)
        }
    }
}
