import XCTest
@testable import MonitorCore

/// FR10. Uses a scratch defaults suite so the user's real names are never touched.
final class MonitorNamesTests: XCTestCase {
    private var suite = ""
    private var names: MonitorNames!
    private let dell = MonitorIdentity(name: "DELL G3223D", vendor: 0x10AC, model: 53565, serial: 809583180, alphanumericSerial: "15YCXG3", displayID: 3)
    private let omen = MonitorIdentity(name: "HP OMEN 27", vendor: 0x22F0, model: 1, serial: 2, alphanumericSerial: "CN1234", displayID: 4)

    override func setUp() {
        suite = "dev.marty.MonitorMenu.tests.\(UUID().uuidString)"
        names = MonitorNames(defaults: UserDefaults(suiteName: suite)!)
    }
    override func tearDown() { UserDefaults.standard.removePersistentDomain(forName: suite) }

    func testRoundTripAndClear() {
        XCTAssertNil(names.name(for: dell))
        XCTAssertEqual(names.displayName(for: dell), "DELL G3223D")
        names.set("Desk", for: dell)
        XCTAssertEqual(names.displayName(for: dell), "Desk")
        XCTAssertEqual(MonitorNames(defaults: UserDefaults(suiteName: suite)!).name(for: dell), "Desk", "persists across instances (and processes)")
        names.set("   ", for: dell)
        XCTAssertNil(names.name(for: dell), "whitespace clears")
        names.set(String(repeating: "x", count: 100), for: dell)
        XCTAssertEqual(names.name(for: dell)?.count, 64, "bounded")
    }

    /// M7: two monitors that share a CoreGraphics id (or have none) must still keep separate names.
    func testNamesAreKeyedBySerialNotDisplayID() {
        var a = dell, b = omen
        a.displayID = nil; b.displayID = nil
        names.set("Left", for: a); names.set("Right", for: b)
        XCTAssertEqual(names.name(for: a), "Left")
        XCTAssertEqual(names.name(for: b), "Right")
        var replugged = dell; replugged.displayID = 9
        XCTAssertEqual(names.name(for: replugged), "Left", "the name follows the serial through a new display id")
    }

    func testResolutionPrefersTheUsersName() {
        names.set("Desk", for: dell); names.set("Omen Dell", for: omen)   // a user name that contains another monitor's model word
        let ids = [dell, omen]
        XCTAssertEqual(names.match("desk", in: ids)?.key, dell.key)
        XCTAssertEqual(names.match("omen dell", in: ids)?.key, omen.key, "exact user name beats a substring of a model name")
        XCTAssertEqual(names.match("G3223D", in: ids)?.key, dell.key, "model name still matches")
        XCTAssertEqual(names.match("15YCXG3", in: ids)?.key, dell.key, "serial matches")
        XCTAssertEqual(names.match("4", in: ids)?.key, omen.key, "display id matches")
        XCTAssertEqual(names.match("", in: ids)?.key, dell.key, "empty selector is the first monitor")
        XCTAssertNil(names.match("sideboard", in: ids))
    }
}
