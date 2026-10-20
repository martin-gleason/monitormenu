import XCTest
@testable import SwitchCore

/// Talks to real hardware. Runs only with SWITCHBAR_LIVE=1 and an external monitor attached.
/// Reads only; it never writes to the monitor.
final class LiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWITCHBAR_LIVE"] == "1", "set SWITCHBAR_LIVE=1 to run against hardware")
    }

    func testDiscoversAMonitorWithCapabilities() throws {
        let monitors = MonitorDiscovery.discover()
        XCTAssertFalse(monitors.isEmpty, "FR1: at least one DDC-capable external monitor")
        for m in monitors {
            let caps = try m.loadCapabilities()
            XCTAssertFalse(caps.vcp.isEmpty, "\(m.name) advertised nothing")
            XCTAssertNotNil(m.identity.displayID, "\(m.name) matched to a CoreGraphics display")
            let v = try m.get(0xDF)
            XCTAssertGreaterThanOrEqual(v.current, 0x0200, "\(m.name) MCCS version reads as \(v.current)")
            print("live: \(m.name) display \(m.identity.displayID ?? 0) inputs \(m.inputs()) pip \(m.hasPiP)")
        }
    }
}
