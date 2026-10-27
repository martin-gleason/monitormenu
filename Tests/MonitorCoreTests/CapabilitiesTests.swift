// Created: 2026-10-19 19:23 -05:00 · Edited: 2026-10-27 09:26 -05:00
import XCTest
@testable import MonitorCore

/// FR1, FR2, FR4, NFR5 — the whitelist is read from the monitor, not assumed. M2.
final class CapabilitiesTests: XCTestCase {
    func testParsesG3223DFixture() {
        let c = Capabilities.parse(Fixtures.g3223d)
        XCTAssertEqual(c.model, "G3223D")
        XCTAssertEqual(c.mccsVersion, "2.1")
        XCTAssertEqual(c.values(for: VCP.inputSource), [0x1B, 0x0F, 0x11, 0x12], "nested input list (M2)")
        XCTAssertEqual(c.values(for: VCP.pipMode), [0x00, 0x01, 0x02, 0x21, 0x22, 0x24, 0x29, 0x2A, 0x2D, 0x2E])
        XCTAssertEqual(c.values(for: VCP.powerMode), [0x01, 0x04, 0x05])
        XCTAssertTrue(c.advertises(VCP.brightness))
        XCTAssertNil(c.values(for: VCP.brightness), "continuous code has no value list")
        XCTAssertTrue(c.advertises(0xFD))
        XCTAssertFalse(c.advertises(0x11), "0x11 is an input value, not a code (M2 catches flattening)")
        XCTAssertEqual(c.vcp.count, 40)
    }

    func testParsesPlainMonitorWithoutOuterParens() {
        let c = Capabilities.parse(Fixtures.plain)
        XCTAssertEqual(c.model, "PLAIN")
        XCTAssertEqual(c.values(for: VCP.inputSource), [0x0F, 0x11])
        XCTAssertFalse(c.advertises(VCP.pipMode), "FR4: no PiP item when the monitor does not advertise it")
    }

    func testGarbageYieldsEmptyWhitelist() {
        let c = Capabilities.parse("6E 80 BE 6E 80 BE")
        XCTAssertTrue(c.vcp.isEmpty)
        XCTAssertNil(c.model)
    }
}
