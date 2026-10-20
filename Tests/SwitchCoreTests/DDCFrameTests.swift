import XCTest
@testable import SwitchCore

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
        let body: [UInt8] = [0x80 | UInt8(3 + frag.count), 0xE3, 0x00, 0x00] + frag
        let reply = [UInt8(0x6E)] + body + [0x00]
        XCTAssertEqual(try DDCFrame.parseCapabilitiesReply(reply, expectingOffset: 0), frag)
        XCTAssertThrowsError(try DDCFrame.parseCapabilitiesReply(reply, expectingOffset: 14))
        let empty: [UInt8] = [0x6E, 0x83, 0xE3, 0x00, 0x0E, 0x00]
        XCTAssertEqual(try DDCFrame.parseCapabilitiesReply(empty, expectingOffset: 14), [], "empty fragment ends the string")
    }
}
