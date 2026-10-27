// Created: 2026-10-19 19:23 -05:00 · Edited: 2026-10-27 09:11 -05:00
import XCTest
@testable import MonitorCore

/// NFR5, D3: the only write path refuses anything the monitor did not advertise. M1, M4.
final class WhitelistTests: XCTestCase {
    func testUnadvertisedCodeIsRefusedBeforeAnyI2C() {
        let (m, ch) = Fixtures.monitor(caps: Fixtures.plain)
        XCTAssertThrowsError(try m.set(VCP.pipMode, 0x21)) { XCTAssertEqual($0 as? DDCError, .notAdvertised(code: 0xE9)) }
        XCTAssertThrowsError(try m.set(0x62, 50))
        XCTAssertTrue(ch.writes.isEmpty, "nothing reached the bus (M1)")
    }

    func testUnadvertisedValueIsRefused() {
        let (m, ch) = Fixtures.monitor(caps: Fixtures.g3223d)
        XCTAssertThrowsError(try m.setInput(0x10)) { XCTAssertEqual($0 as? DDCError, .valueNotAdvertised(code: 0x60, value: 0x10)) }
        XCTAssertThrowsError(try m.setPiPMode(0x41), "m1ddc's 2×2 value is not advertised by the G3223D")
        XCTAssertTrue(ch.writes.isEmpty)
    }

    func testAdvertisedWritesGoThrough() throws {
        let ch = RecordingChannel(); ch.replies = [LockTests.presetReply(0x00),                                                      // D14: the Dell's preset, unlocked
                                                   Fixtures.sealed([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x38])]   // brightness 56/100
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        try m.setInput(0x11)
        try m.setBrightness(56)
        try m.setPiPMode(0x24)
        try m.setPower(0x04)
        XCTAssertEqual(ch.writes, [DDCFrame.setVCP(0x60, 0x11), DDCFrame.getVCP(0xF0), DDCFrame.getVCP(0x10), DDCFrame.setVCP(0x10, 56), DDCFrame.setVCP(0xE9, 0x24), DDCFrame.setVCP(0xD6, 0x04)],
                       "the first brightness write on a Dell is preceded by one read of the lock preset (D14) and one of its range; discrete codes need neither")
    }

    /// M9 (review A2-3): a continuous code is never written before its maximum is known, on any surface.
    func testContinuousWriteReadsTheMaximumFirst() throws {
        let ch = RecordingChannel(); ch.replies = [Fixtures.replyRedGain]          // 0x16: max 100
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        XCTAssertThrowsError(try m.set(0x16, 500)) { XCTAssertEqual($0 as? DDCError, .valueNotAdvertised(code: 0x16, value: 500)) }
        XCTAssertEqual(ch.writes, [DDCFrame.getVCP(0x16)], "one read of the range, and no set frame reached the bus")
        XCTAssertThrowsError(try m.set(0x16, 0xFFFF))
        XCTAssertNoThrow(try m.set(0x16, 100))
        XCTAssertEqual(ch.writes.count, 2, "the range was read once; the accepted write is the only set frame")
    }

    func testFactoryResetCodesAreNeverOffered() {
        // The G3223D advertises 0x04, 0x05 and 0x08. They must still be refused (M4).
        let (m, ch) = Fixtures.monitor(caps: Fixtures.g3223d)
        for code in [UInt8(0x04), 0x05, 0x08] {
            XCTAssertTrue(m.capabilities!.advertises(code))
            XCTAssertThrowsError(try m.set(code, 1)) { XCTAssertEqual($0 as? DDCError, .refusedFactoryReset(code: code)) }
        }
        XCTAssertTrue(ch.writes.isEmpty)
    }

    /// Review C8: a continuous code is bounded by the maximum the monitor last reported.
    func testContinuousValueAboveReportedMaximumIsRefused() throws {
        let ch = RecordingChannel(); ch.replies = [Fixtures.replyRedGain]          // 0x16: max 100
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        _ = try m.get(0x16)
        XCTAssertThrowsError(try m.set(0x16, 101)) { XCTAssertEqual($0 as? DDCError, .valueNotAdvertised(code: 0x16, value: 101)) }
        XCTAssertNoThrow(try m.set(0x16, 100))
        XCTAssertEqual(ch.writes.count, 2, "one get request, one accepted write")
    }

    func testNoCapabilitiesMeansNoWrites() {
        let link = DDCMonitorLink(channel: RecordingChannel(), label: "t")
        let m = Monitor(identity: MonitorIdentity(name: "x", vendor: 0, model: 0, serial: 0), link: link)
        XCTAssertThrowsError(try m.setBrightness(10))
    }
}
