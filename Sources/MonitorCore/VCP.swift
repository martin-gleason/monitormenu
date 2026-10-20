import Foundation

/// MCCS codes the app knows how to label. Anything else the monitor advertises is still
/// reachable by raw code through `monitorctl`, shown as hex (D3).
public enum VCP {
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    public static let inputSource: UInt8 = 0x60
    public static let powerMode: UInt8 = 0xD6
    public static let pipMode: UInt8 = 0xE9      // Dell PIP/PBP layout (vendor-specific range)
    public static let pipSource: UInt8 = 0xEA    // Dell PIP/PBP secondary input

    /// PiP/PbP lives in the vendor-specific VCP range, so the codes are per manufacturer (NFR8).
    /// Keyed by the EDID manufacturer id (Dell = 0x10AC). A vendor absent here has no PiP item until
    /// a mapping is added; HP's codes are unknown until the Omen arrives (D10).
    public static let vendorPiPCodes: [UInt32: (mode: UInt8, source: UInt8)] = [
        0x10AC: (0xE9, 0xEA),
    ]
    public static func pipCodes(vendor: UInt32) -> (mode: UInt8, source: UInt8)? { vendorPiPCodes[vendor] }

    /// off · small · large · split (also pip/on/pbp/half) · 0xNN · decimal → the PiP mode value.
    public static func pipCode(from text: String) -> UInt8? {
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        switch key {
        case "off", "0": return 0x00
        case "small", "pip", "on": return 0x21
        case "large": return 0x22
        case "split", "pbp", "half": return 0x24
        default:
            if key.hasPrefix("0x"), let v = UInt8(key.dropFirst(2), radix: 16) { return v }
            return UInt8(key)
        }
    }
    public static let factoryResets: Set<UInt8> = [0x04, 0x05, 0x06, 0x08, 0x0A]  // never offered (NFR5)

    /// MCCS 2.2 input source values (table 7.3). Low byte of VCP 0x60.
    public static let inputNames: [UInt8: String] = [
        0x01: "VGA 1", 0x02: "VGA 2", 0x03: "DVI 1", 0x04: "DVI 2", 0x05: "Composite 1", 0x06: "Composite 2",
        0x07: "S-Video 1", 0x08: "S-Video 2", 0x09: "Tuner 1", 0x0A: "Tuner 2", 0x0B: "Tuner 3",
        0x0C: "Component 1", 0x0D: "Component 2", 0x0E: "Component 3",
        0x0F: "DisplayPort 1", 0x10: "DisplayPort 2", 0x11: "HDMI 1", 0x12: "HDMI 2",
        0x1B: "USB-C",   // observed on Dell; m1ddc documents 27 as USB-C
    ]

    /// Short aliases accepted by the CLI, URL scheme and intents.
    public static let inputAliases: [String: UInt8] = [
        "dp": 0x0F, "dp1": 0x0F, "displayport": 0x0F, "displayport1": 0x0F,
        "dp2": 0x10, "displayport2": 0x10,
        "hdmi": 0x11, "hdmi1": 0x11, "hdmi2": 0x12,
        "usbc": 0x1B, "usb-c": 0x1B, "typec": 0x1B, "thunderbolt": 0x1B,
    ]

    public static let powerNames: [UInt8: String] = [0x01: "On", 0x02: "Standby", 0x03: "Suspend", 0x04: "Off (standby)", 0x05: "Off"]

    /// Vendor value labels, keyed by (code, value). Consulted only when the capabilities string
    /// advertises that code (NFR8). Dell PiP labels come from m1ddc's documentation (D7);
    /// the G3223D's other values stay hex until the owner's mapping session (`O5`).
    public static let vendorLabels: [UInt8: [UInt8: String]] = [
        pipMode: [0x00: "Off", 0x21: "PiP small", 0x22: "PiP large", 0x24: "PbP 50/50",
                  0x2B: "PbP 26/74", 0x2C: "PbP 74/26", 0x41: "PbP 2×2"],
    ]

    public static func label(code: UInt8, value: UInt8) -> String {
        switch code {
        case inputSource: return inputNames[value] ?? String(format: "Input 0x%02X", value)
        case powerMode: return powerNames[value] ?? String(format: "Power 0x%02X", value)
        default: return vendorLabels[code]?[value] ?? String(format: "0x%02X", value)
        }
    }

    public static func inputCode(from text: String) -> UInt8? {
        let key = text.lowercased().replacingOccurrences(of: " ", with: "")
        if let c = inputAliases[key] { return c }
        if key.hasPrefix("0x"), let v = UInt8(key.dropFirst(2), radix: 16) { return v }
        if let v = UInt8(key) { return v }
        return nil
    }
}
