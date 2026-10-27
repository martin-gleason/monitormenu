// Created: 2026-10-21 10:05 -05:00 · Edited: 2026-10-27 09:26 -05:00
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
    override func tearDown() {
        // removePersistentDomain leaves an empty plist behind in ~/Library/Preferences (review F2 #5); delete it too.
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
    }

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

    func testResolutionPrefersTheUsersName() throws {
        names.set("Desk", for: dell); names.set("Omen Dell", for: omen)   // a user name that contains another monitor's model word
        // Review F2 #1: the answer must not depend on discovery order, so every case runs both ways round.
        for ids in [[dell, omen], [omen, dell]] {
            XCTAssertEqual(try names.match("desk", in: ids)?.key, dell.key)
            XCTAssertEqual(try names.match("omen dell", in: ids)?.key, omen.key, "exact user name beats a substring of a model name")
            XCTAssertEqual(try names.match("dell", in: ids)?.key, omen.key, "'dell' is a substring of one user name (Omen Dell) and that tier runs before model names; same answer both ways round")
            XCTAssertEqual(try names.match("G3223D", in: ids)?.key, dell.key, "model name still matches")
            XCTAssertEqual(try names.match("15YCXG3", in: ids)?.key, dell.key, "serial matches")
            XCTAssertEqual(try names.match("4", in: ids)?.key, omen.key, "display id matches")
            XCTAssertNil(try names.match("sideboard", in: ids))
        }
        XCTAssertEqual(try names.match("", in: [dell, omen])?.key, dell.key, "empty selector is the first monitor")
    }

    /// Review F2 #1: a user name may not hijack another monitor's serial, display id or exact model name.
    func testUnambiguousSelectorsBeatUserNames() throws {
        names.set("CN1234", for: dell)        // the Omen's serial, used as the Dell's name
        XCTAssertEqual(try names.match("CN1234", in: [dell, omen])?.key, dell.key, "exact user name is the top tier")
        names.set("HP OMEN 27", for: dell)    // the Omen's exact model name as the Dell's name
        XCTAssertEqual(try names.match("HP OMEN 27", in: [omen, dell])?.key, dell.key, "exact user name still wins; the owner chose it")
        names.set("4", for: dell)
        XCTAssertEqual(try names.match("4", in: [omen, dell])?.key, dell.key)
        names.clear(for: dell)
        XCTAssertEqual(try names.match("CN1234", in: [dell, omen])?.key, omen.key, "with no user name, the serial tier resolves")
        XCTAssertEqual(try names.match("4", in: [dell, omen])?.key, omen.key)
    }

    /// Review F2 #1: two monitors of the same model, one named. A model-word selector fits both and is refused.
    func testSameModelSelectorIsRefusedNotGuessed() throws {
        var dell2 = dell; dell2.serial = 1; dell2.alphanumericSerial = "ZZ9999"; dell2.displayID = 5
        names.set("Desk", for: dell)
        for ids in [[dell, dell2], [dell2, dell]] {
            XCTAssertThrowsError(try names.match("g3223d", in: ids)) { e in
                guard case DDCError.ambiguousMonitor(let sel, let hits) = e else { return XCTFail("\(e)") }
                XCTAssertEqual(sel, "g3223d"); XCTAssertEqual(hits.count, 2)
            }
            XCTAssertEqual(try names.match("desk", in: ids)?.key, dell.key, "the named one is reachable by name")
            XCTAssertEqual(try names.match("ZZ9999", in: ids)?.key, dell2.key, "the unnamed one is reachable by serial")
            XCTAssertEqual(try names.match("5", in: ids)?.key, dell2.key, "or by display id")
        }
    }
}
