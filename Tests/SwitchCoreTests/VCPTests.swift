import XCTest
@testable import SwitchCore

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
        XCTAssertEqual(VCP.label(code: VCP.pipMode, value: 0x2E), "0x2E", "unmapped G3223D value stays hex until O5")
        XCTAssertEqual(VCP.label(code: VCP.inputSource, value: 0x1B), "USB-C")
        XCTAssertEqual(VCP.label(code: VCP.powerMode, value: 0x04), "Off (standby)")
    }

    func testDiscoveryKeyParsing() {
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "dispext0:dcpav-service-epic:0"), "dispext0")
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "dispext0@88000000"), "dispext0")
        XCTAssertEqual(MonitorDiscovery.displayKey(fromName: "disp0:dcpav-service-epic:0"), "disp0")
        XCTAssertNil(MonitorDiscovery.displayKey(fromName: "AppleCLCD2"))
    }
}
