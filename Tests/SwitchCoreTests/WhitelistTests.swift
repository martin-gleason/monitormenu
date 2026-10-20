import XCTest
@testable import SwitchCore

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
        let (m, ch) = Fixtures.monitor(caps: Fixtures.g3223d)
        try m.setInput(0x11)
        try m.setBrightness(56)
        try m.setPiPMode(0x24)
        try m.setPower(0x04)
        XCTAssertEqual(ch.writes, [DDCFrame.setVCP(0x60, 0x11), DDCFrame.setVCP(0x10, 56), DDCFrame.setVCP(0xE9, 0x24), DDCFrame.setVCP(0xD6, 0x04)])
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
