import XCTest
@testable import MonitorCore

/// Framing checked against bytes the G3223D actually sent and accepted. M3.
final class DDCFrameTests: XCTestCase {
    func testSetVCPFrameMatchesM1DDCLayout() {
        // m1ddc: [0x84, 0x03, code, hi, lo, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ code ^ hi ^ lo]
        XCTAssertEqual(DDCFrame.setVCP(0x60, 0x0011), [0x84, 0x03, 0x60, 0x00, 0x11, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x60 ^ 0x00 ^ 0x11])
        XCTAssertEqual(DDCFrame.getVCP(0x10), [0x82, 0x01, 0x10, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10])
        XCTAssertEqual(DDCFrame.capabilitiesRequest(offset: 0x0120), [0x83, 0xF3, 0x01, 0x20, 0x6E ^ 0x51 ^ 0x83 ^ 0xF3 ^ 0x01 ^ 0x20])
    }

    func testCurrentInputIsLowByte() throws {
        let r = try DDCFrame.parseVCPReply(Fixtures.replyVolume81, expecting: 0x62)
        XCTAssertEqual(r.current, 81)
        XCTAssertEqual(r.maximum, 100)
        let v = try DDCFrame.parseVCPReply(Fixtures.replyVCPVersion, expecting: 0xDF)
        XCTAssertEqual(v.current, 513, "current is bytes 8–9, not 6–7 (M3)")
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: { let c = RecordingChannel(); c.replies = [Fixtures.replyInputUSBC]; return c }())
        XCTAssertEqual(try m.currentInput(), 0x1B)
    }

    func testReplyForWrongCodeIsRejected() {
        XCTAssertThrowsError(try DDCFrame.parseVCPReply(Fixtures.replyRedGain, expecting: 0x10))
        XCTAssertThrowsError(try DDCFrame.parseVCPReply([0x6E, 0x80, 0xBE], expecting: 0x10), "null message")
    }

    func testCapabilitiesFragmentParsing() throws {
        let frag: [UInt8] = Array("(prot(monitor)".utf8)
        let reply = Fixtures.sealed([0x6E, 0x80 | UInt8(3 + frag.count), 0xE3, 0x00, 0x00] + frag)
        XCTAssertEqual(try DDCFrame.parseCapabilitiesReply(reply, expectingOffset: 0), frag)
        XCTAssertThrowsError(try DDCFrame.parseCapabilitiesReply(reply, expectingOffset: 14))
        let empty = Fixtures.sealed([0x6E, 0x83, 0xE3, 0x00, 0x0E])
        XCTAssertEqual(try DDCFrame.parseCapabilitiesReply(empty, expectingOffset: 14), [], "empty fragment ends the string")
    }

    /// M5: a corrupted byte on the shared bus must be rejected, not shown as a value.
    func testChecksumMismatchIsRejected() {
        var r = Fixtures.replyVolume81; r[9] = 0x05          // current 81 → 5, checksum now wrong
        XCTAssertThrowsError(try DDCFrame.parseVCPReply(r, expecting: 0x62)) { XCTAssertEqual($0 as? DDCError, .badReply("checksum mismatch")) }
        var i = Fixtures.replyInputUSBC; i[9] = 0x11         // USB-C → HDMI 1 by one flipped byte
        XCTAssertThrowsError(try DDCFrame.parseVCPReply(i, expecting: 0x60))
        XCTAssertEqual(DDCFrame.replyChecksum(Fixtures.replyVCPVersion[0..<10]), 0x68, "checksum rule reproduces the G3223D's own bytes")
        XCTAssertEqual(DDCFrame.replyChecksum([0x6E, 0x80]), 0xBE, "null message checksum")
    }

    /// Review A2-6: MCCS result byte 0x01 means "unsupported VCP"; its value bytes are not a value.
    func testUnsupportedResultByteIsRejected() {
        let r = Fixtures.sealed([0x6E, 0x88, 0x02, 0x01, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try DDCFrame.parseVCPReply(r, expecting: 0x60)) { XCTAssertTrue("\($0)".contains("unsupported")) }
        let (m, ch) = Fixtures.monitor(caps: Fixtures.g3223d); ch.replies = [r]
        XCTAssertThrowsError(try m.currentInput(), "no input 0x00 out of an unsupported reply")
    }

    /// M8 (review A2-1): a timed-out call is never retried; the abandoned call is still on the bus and a
    /// retry would land on top of it. One slow read means one read, and the error comes back at the deadline.
    func testTimeoutIsNotRetried() {
        final class Slow: I2CChannel {
            var reads = 0; let lock = NSLock()
            func write(_ bytes: [UInt8]) throws {}
            func read(count: Int) throws -> [UInt8] { lock.lock(); reads += 1; lock.unlock(); Thread.sleep(forTimeInterval: 0.5); return Fixtures.replyVolume81 }
        }
        let slow = Slow()
        let link = DDCMonitorLink(channel: DeadlineChannel(slow, timeout: 0.05), label: "slow")
        link.timing.replyDelay = 0; link.timing.commandGap = 0   // attempts stay at the shipped default
        let t0 = Date()
        XCTAssertThrowsError(try link.read(0x62)) { XCTAssertEqual($0 as? DDCError, .timeout("I2C read")) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.3, "back at the deadline, not after five attempts")
        Thread.sleep(forTimeInterval: 0.6)
        slow.lock.lock(); let reads = slow.reads; slow.lock.unlock()
        XCTAssertEqual(reads, 1, "exactly one read was issued")
    }

    /// Review A2-2: a hung channel blocks only its own queue. Many abandoned calls on it must not stop a
    /// healthy channel from reaching its transport (the old shared pool died at 64).
    func testHungChannelDoesNotStarveAnother() {
        final class Hung: I2CChannel {
            func write(_ bytes: [UInt8]) throws { Thread.sleep(forTimeInterval: 3) }
            func read(count: Int) throws -> [UInt8] { Thread.sleep(forTimeInterval: 3); return [] }
        }
        let hung = DeadlineChannel(Hung(), timeout: 0.01)
        for _ in 0..<70 { XCTAssertThrowsError(try hung.write([0x01])) }
        let healthy = DeadlineChannel(RecordingChannel(), timeout: 0.5)
        let t0 = Date()
        XCTAssertNoThrow(try healthy.write([0x01]))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.4, "the healthy channel answered at once")
    }

    /// M6: a transport call that never returns must surface as a timeout, not a hang (NFR4).
    func testDeadlineChannelTimesOut() {
        final class Slow: I2CChannel {
            func write(_ bytes: [UInt8]) throws {}
            func read(count: Int) throws -> [UInt8] { Thread.sleep(forTimeInterval: 0.6); return Fixtures.replyVolume81 }
        }
        let ch = DeadlineChannel(Slow(), timeout: 0.15)
        let t0 = Date()
        XCTAssertThrowsError(try ch.read(count: 11)) { XCTAssertEqual($0 as? DDCError, .timeout("I2C read")) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.5, "returned at the deadline, not when the slow read finished")
        let quick = DeadlineChannel(RecordingChannel(), timeout: 0.5)
        XCTAssertNoThrow(try quick.write([0x01]))
    }
}
