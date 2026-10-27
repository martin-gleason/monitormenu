// Created: 2026-10-27 09:10 -05:00 · Edited: 2026-10-27 09:10 -05:00
import XCTest
@testable import MonitorCore

/// D14: a vendor preset that makes the monitor ignore brightness and contrast is detected and the
/// writes are refused with a message instead of sent. M10 (vendor key), M11 (write despite the lock).
final class LockTests: XCTestCase {
    /// The G3223D's preset reply with Smart HDR on (`0xF0` = 0x34) and off (0x0F), as the monitor frames them.
    static func presetReply(_ value: UInt8) -> [UInt8] { Fixtures.sealed([0x6E, 0x88, 0x02, 0x00, 0xF0, 0x00, 0x00, 0xFF, 0x00, value]) }
    /// Brightness 56/100: the range read a first brightness write makes (M9) consumes one of these.
    static let brightnessReply = Fixtures.sealed([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x38])

    func testSmartHDRLocksTheDell() throws {
        let ch = RecordingChannel(); ch.replies = [Self.presetReply(0x34)]
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d)
        let dell = Monitor(identity: m.identity, link: DDCMonitorLink(channel: ch, label: "t"), capabilities: m.capabilities)
        dell.link.timing.replyDelay = 0; dell.link.timing.commandGap = 0; dell.link.timing.attempts = 1
        XCTAssertEqual(try dell.pictureLock(), "Smart HDR")
        XCTAssertEqual(dell.lockedBy, "Smart HDR")
        XCTAssertEqual(ch.writes, [DDCFrame.getVCP(0xF0)], "one read of the preset code")
    }

    func testOtherPresetsDoNotLock() throws {
        let ch = RecordingChannel(); ch.replies = [Self.presetReply(0x0F)]
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        XCTAssertNil(try m.pictureLock())
        XCTAssertNil(m.lockedBy)
    }

    /// M11: while the last read said locked, brightness and contrast never reach the bus; other codes still do.
    func testLockedCodesAreNotWritten() throws {
        let ch = RecordingChannel(); ch.replies = [Self.presetReply(0x34)]
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        try m.pictureLock()
        XCTAssertThrowsError(try m.setBrightness(50)) { XCTAssertEqual($0 as? DDCError, .locked(code: 0x10, by: "Smart HDR")) }
        XCTAssertThrowsError(try m.setContrast(50))
        XCTAssertEqual(ch.writes, [DDCFrame.getVCP(0xF0)], "no set frame reached the bus while locked")
        XCTAssertNoThrow(try m.setInput(0x11), "the lock covers brightness and contrast only")
        XCTAssertEqual(DDCError.locked(code: 0x10, by: "Smart HDR").description, "brightness is locked by the monitor's Smart HDR — turn it off in the monitor's menu")
    }

    /// Once the preset reads as something else, writes go through again (after the usual range read, M9).
    func testUnlockingClearsTheRefusal() throws {
        let ch = RecordingChannel(); ch.replies = [Self.presetReply(0x34), Self.presetReply(0x0F), Self.brightnessReply]
        let (m, _) = Fixtures.monitor(caps: Fixtures.g3223d, channel: ch)
        try m.pictureLock()
        XCTAssertThrowsError(try m.setBrightness(50))
        XCTAssertNil(try m.pictureLock())
        XCTAssertNoThrow(try m.setBrightness(50))
        XCTAssertEqual(ch.writes.last, DDCFrame.setVCP(0x10, 50))
    }

    /// M10, NFR8: the table is per vendor. Another maker's monitor advertising 0xF0 = 0x34 is not locked, and no I2C happens.
    func testLockIsVendorKeyed() throws {
        let ch = RecordingChannel(); ch.replies = [Self.brightnessReply]   // no preset reply is scripted: none may be asked for
        let link = DDCMonitorLink(channel: ch, label: "t"); link.timing.replyDelay = 0; link.timing.commandGap = 0; link.timing.attempts = 1
        let hp = Monitor(identity: MonitorIdentity(name: "OMEN", vendor: 0x22F0, model: 1, serial: 1), link: link, capabilities: Capabilities.parse(Fixtures.g3223d))
        XCTAssertNil(try hp.pictureLock())
        XCTAssertTrue(ch.writes.isEmpty, "a vendor without a locking preset is never asked (NFR8)")
        XCTAssertNoThrow(try hp.setBrightness(10))
        XCTAssertEqual(ch.writes.last, DDCFrame.setVCP(0x10, 10))
    }

    /// A Dell that does not advertise the preset code is never asked either.
    func testUnadvertisedPresetCodeIsNeverRead() throws {
        let (m, ch) = Fixtures.monitor(caps: Fixtures.plain)
        XCTAssertNil(try m.pictureLock())
        XCTAssertTrue(ch.writes.isEmpty)
    }
}
