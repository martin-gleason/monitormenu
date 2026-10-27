// Created: 2026-10-27 09:26 -05:00 · Edited: 2026-10-27 09:26 -05:00
import XCTest
@testable import MonitorCore

/// C4-T1: the capabilities string is read from the monitor once and remembered per serial (M12).
/// Uses a scratch defaults suite so the user's real cache is never touched.
final class CapabilitiesCacheTests: XCTestCase {
    private var suite = ""
    private var cache: CapabilitiesCache!
    private let dell = MonitorIdentity(name: "DELL G3223D", vendor: 0x10AC, model: 53565, serial: 809583180, alphanumericSerial: "15YCXG3", displayID: 3)
    private let omen = MonitorIdentity(name: "HP OMEN 27", vendor: 0x22F0, model: 1, serial: 2, alphanumericSerial: "CN1234", displayID: 4)

    override func setUp() {
        suite = "dev.marty.MonitorMenu.tests.\(UUID().uuidString)"
        cache = CapabilitiesCache(defaults: UserDefaults(suiteName: suite)!)
    }
    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    /// The monitor's replies to a capabilities request: 32-byte fragments at each offset, then an empty one.
    static func capabilitiesReplies(for s: String) -> [[UInt8]] {
        let bytes = Array(s.utf8)
        var out: [[UInt8]] = []
        var off = 0
        while true {
            let frag = Array(bytes[off..<min(off + 32, bytes.count)])
            let body: [UInt8] = [0x6E, 0x80 | UInt8(3 + frag.count), 0xE3, UInt8(off >> 8), UInt8(off & 0xFF)] + frag
            out.append(Fixtures.sealed(body))
            if frag.isEmpty { return out }
            off += frag.count
        }
    }

    func testFirstReadComesFromTheMonitorAndIsStored() throws {
        let ch = RecordingChannel(); ch.replies = Self.capabilitiesReplies(for: Fixtures.plain)
        let m = Monitor(identity: dell, link: Fixtures.monitor(caps: Fixtures.plain, channel: ch).0.link)
        let caps = try m.loadCapabilities(cache: cache)
        XCTAssertEqual(caps.model, "PLAIN")
        XCTAssertEqual(ch.writes.count, 4, "three fragments and the empty terminator were asked for")
        XCTAssertEqual(cache.raw(for: dell), Fixtures.plain, "stored for the next process")
    }

    func testCacheHitSkipsTheMonitor() throws {
        cache.store(Fixtures.g3223d, for: dell)
        let ch = RecordingChannel()   // no replies: any I2C would throw
        let m = Monitor(identity: dell, link: Fixtures.monitor(caps: Fixtures.plain, channel: ch).0.link)
        let caps = try m.loadCapabilities(cache: cache)
        XCTAssertEqual(caps.model, "G3223D")
        XCTAssertTrue(caps.advertises(0xE9))
        XCTAssertTrue(ch.writes.isEmpty, "nothing reached the bus")
    }

    func testFreshBypassesAndReplacesTheCache() throws {
        cache.store(Fixtures.g3223d, for: dell)
        let ch = RecordingChannel(); ch.replies = Self.capabilitiesReplies(for: Fixtures.plain)
        let m = Monitor(identity: dell, link: Fixtures.monitor(caps: Fixtures.plain, channel: ch).0.link)
        XCTAssertEqual(try m.loadCapabilities(cache: cache, fresh: true).model, "PLAIN")
        XCTAssertEqual(cache.raw(for: dell), Fixtures.plain, "the fresh string replaced the old one")
    }

    /// M12: an entry is for one monitor. Another serial gets nothing and reads its own monitor.
    func testCacheIsPerMonitor() throws {
        cache.store(Fixtures.g3223d, for: dell)
        XCTAssertNil(cache.raw(for: omen))
        let ch = RecordingChannel()   // no replies: the read must fail, proving it was attempted
        let m = Monitor(identity: omen, link: Fixtures.monitor(caps: Fixtures.plain, channel: ch).0.link)
        XCTAssertThrowsError(try m.loadCapabilities(cache: cache))
        XCTAssertFalse(ch.writes.isEmpty, "the Omen's own monitor was asked, not the Dell's cache")
        XCTAssertNil(m.capabilities, "no whitelist was adopted from another monitor")
    }

    func testCorruptEntryIsIgnored() throws {
        cache.store("garbage", for: dell)
        XCTAssertNil(cache.raw(for: dell))
        let ch = RecordingChannel(); ch.replies = Self.capabilitiesReplies(for: Fixtures.plain)
        let m = Monitor(identity: dell, link: Fixtures.monitor(caps: Fixtures.plain, channel: ch).0.link)
        XCTAssertEqual(try m.loadCapabilities(cache: cache).model, "PLAIN")
        cache.forget(dell)
        XCTAssertNil(cache.raw(for: dell))
    }
}
