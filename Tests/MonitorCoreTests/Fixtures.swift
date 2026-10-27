// Created: 2026-10-19 19:23 -05:00 · Edited: 2026-10-27 09:26 -05:00
import Foundation
@testable import MonitorCore

enum Fixtures {
    /// Captured from the Dell G3223D over IOAVService on 2026-10-19 (`monitorctl capabilities`).
    static let g3223d = "(prot(monitor)type(LCD)model(G3223D)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B 0C) 16 18 1A 52 60(1B 0F 11 12 ) 62 AC AE B2 B6 C6 C8 C9 CA CC(02 0A 03 04 08 09 0D 06 ) D6(01 04 05) DC(00 05 ) DF E0 E1 E2(00 20 21 22 2F 04 1E 1F 0E 12 0B 14 27 23 24 3A ) E3 E4(00 01) E5 E8 E9(00 01 02 21 22 24 29 2A 2D 2E ) EA F0(0D 0E 0F 10 11 13 31 32 34 36 ) EC(01 02 03 04 06) F1 F2 F4(10 11 12 13 14 15 16 17 20 21 22 30 31 32 33 40 41 42 43 44 ) FD)mswhql(1)asset_eep(40)mccs_ver(2.1))"

    /// A monitor with no PiP, no outer parentheses, continuous brightness only.
    static let plain = "prot(monitor)type(LCD)model(PLAIN)cmds(01 02 03)vcp(10 12 60(0F 11))mccs_ver(2.2)"

    /// Raw replies captured from the G3223D on 2026-10-19 (`MONITORMENU_DEBUG=1 monitorctl get …`).
    static let replyVolume81: [UInt8]   = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x51, 0xE3]
    static let replyVCPVersion: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0xDF, 0x00, 0xFF, 0xFF, 0x02, 0x01, 0x68]
    static let replyInputUSBC: [UInt8]  = [0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x1B, 0x1B, 0x1B, 0x1B, 0xD4]
    static let replyRedGain: [UInt8]    = [0x6E, 0x88, 0x02, 0x00, 0x16, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA2]

    /// Appends the DDC reply checksum (0x50 ^ every byte) so hand-built replies pass validation.
    static func sealed(_ bytes: [UInt8]) -> [UInt8] { bytes + [DDCFrame.replyChecksum(bytes[...])] }

    static func monitor(caps: String, channel: RecordingChannel = RecordingChannel()) -> (Monitor, RecordingChannel) {
        let link = DDCMonitorLink(channel: channel, label: "test")
        link.timing.replyDelay = 0; link.timing.commandGap = 0; link.timing.attempts = 1
        let id = MonitorIdentity(name: "Test", vendor: 0x10AC, model: 2, serial: 3)   // Dell, so PiP codes resolve
        return (Monitor(identity: id, link: link, capabilities: Capabilities.parse(caps)), channel)
    }
}
