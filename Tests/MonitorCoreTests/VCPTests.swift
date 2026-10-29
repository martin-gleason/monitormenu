// Created: 2026-10-19 19:23 -05:00 · Edited: 2026-10-29 12:14 -05:00
import XCTest
@testable import MonitorCore

final class VCPTests: XCTestCase {
    func testInputAliases() {
        XCTAssertEqual(VCP.inputCode(from: "hdmi2"), 0x12)
        XCTAssertEqual(VCP.inputCode(from: "HDMI 1"), 0x11)
        XCTAssertEqual(VCP.inputCode(from: "dp"), 0x0F)
        XCTAssertEqual(VCP.inputCode(from: "usb-c"), 0x1B)
        XCTAssertEqual(VCP.inputCode(from: "0x1b"), 0x1B)
        XCTAssertEqual(VCP.inputCode(from: "17"), 0x11)
        XCTAssertNil(VCP.inputCode(from: "scart"))
    }

    func testLabelsFallBackToHex() {
        XCTAssertEqual(VCP.label(code: VCP.pipMode, value: 0x24), "PbP 50/50")
        XCTAssertEqual(VCP.label(code: VCP.pipMode, value: 0x29), "PbP 25/75", "mapped at the desk 2026-10-29 (O5)")
        XCTAssertEqual(VCP.label(code: VCP.pipMode, value: 0x2E), "PbP 75/25", "the duplicate carries the same name as 0x2A")
        XCTAssertEqual(VCP.label(code: VCP.pipMode, value: 0x33), "0x33", "a value no table names stays hex")
        XCTAssertEqual(VCP.label(code: VCP.inputSource, value: 0x1B), "USB-C")
        XCTAssertEqual(VCP.label(code: VCP.powerMode, value: 0x04), "Off (standby)")
    }

    func testPiPAliasesAndVendorCodes() {
        XCTAssertEqual(VCP.pipCode(from: "small"), 0x21)
        XCTAssertEqual(VCP.pipCode(from: "split"), 0x24)
        XCTAssertEqual(VCP.pipCode(from: "25/75"), 0x29)
        XCTAssertEqual(VCP.pipCode(from: "75-25"), 0x2A)
        XCTAssertEqual(VCP.pipCode(from: "off"), 0)
        XCTAssertEqual(VCP.pipCode(from: "0x2E"), 0x2E)
        XCTAssertNil(VCP.pipCode(from: "sideways"))
        XCTAssertEqual(VCP.pipCodes(vendor: 0x10AC)?.mode, 0xE9, "Dell")
        XCTAssertNil(VCP.pipCodes(vendor: 0x22F0), "HP: unknown until the Omen arrives (NFR8)")
        // A Dell fixture has PiP; the same capabilities under an unknown vendor do not (FR4, NFR8).
        let dell = Monitor(identity: MonitorIdentity(name: "d", vendor: 0x10AC, model: 1, serial: 1), link: DDCMonitorLink(channel: RecordingChannel(), label: "d"), capabilities: Capabilities.parse(Fixtures.g3223d))
        XCTAssertTrue(dell.hasPiP); XCTAssertEqual(dell.pipModes().count, 6, "ten advertised, four hidden (D21)")
        let other = Monitor(identity: MonitorIdentity(name: "o", vendor: 0x22F0, model: 1, serial: 1), link: DDCMonitorLink(channel: RecordingChannel(), label: "o"), capabilities: Capabilities.parse(Fixtures.g3223d))
        XCTAssertFalse(other.hasPiP); XCTAssertThrowsError(try other.setPiPMode(0x21))
    }

    func testDiscoveryKeyParsing() {
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "dispext0:dcpav-service-epic:0"), "dispext0")
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "dispext0@88000000"), "dispext0")
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "disp0:dcpav-service-epic:0"), "disp0")
        XCTAssertNil(MonitorDiscovery.displayKey(fromName: "AppleCLCD2"))
    }
}
