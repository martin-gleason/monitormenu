import Foundation

/// The monitor's own list of what it supports, parsed from its DDC capabilities string.
/// This is the whitelist (D3): nothing absent from here is ever offered or written.
public struct Capabilities: Equatable {
    public var model: String?
    public var mccsVersion: String?
    /// VCP code → advertised values (nil = continuous, or not enumerated by the monitor).
    public var vcp: [UInt8: [UInt8]?]
    public var raw: String

    public func advertises(_ code: UInt8) -> Bool { vcp[code] != nil }

    /// Advertised discrete values for a code, or nil when continuous/unlisted.
    public func values(for code: UInt8) -> [UInt8]? { vcp[code] ?? nil }

    /// Parses `prot(monitor)type(LCD)model(G3223D)cmds(01 02)vcp(02 10 14(05 08) 60(0F 11 12))mccs_ver(2.1)`.
    /// Nested parentheses inside `vcp(...)` are the per-code value lists (M2).
    public static func parse(_ s: String) -> Capabilities {
        var caps = Capabilities(model: nil, mccsVersion: nil, vcp: [:], raw: s)
        // Some monitors (Dell) wrap the whole string in one outer pair of parentheses.
        var groups = topLevelGroups(s)
        if groups.count == 1, groups[0].0.isEmpty { groups = topLevelGroups(groups[0].1) }
        for (key, body) in groups {
            switch key {
            case "model": caps.model = body.trimmingCharacters(in: .whitespaces)
            case "mccs_ver": caps.mccsVersion = body.trimmingCharacters(in: .whitespaces)
            case "vcp": caps.vcp = parseVCPList(body)
            default: break
            }
        }
        return caps
    }

    /// Splits `a(…)b(…)` at depth 0 into (key, body) pairs; bodies keep their inner parens.
    static func topLevelGroups(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var key = "", body = "", depth = 0
        for ch in s {
            if ch == "(" {
                if depth > 0 { body.append(ch) }
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if depth == 0 { out.append((key.trimmingCharacters(in: .whitespaces), body)); key = ""; body = "" }
                else { body.append(ch) }
            } else if depth == 0 {
                key.append(ch)
            } else {
                body.append(ch)
            }
        }
        return out
    }

    static func parseVCPList(_ body: String) -> [UInt8: [UInt8]?] {
        var out: [UInt8: [UInt8]?] = [:]
        var token = "", depth = 0, current: UInt8? = nil, values: [UInt8] = []
        func flushToken() {
            guard !token.isEmpty, let v = UInt8(token, radix: 16) else { token = ""; return }
            if depth == 0 { current = v; out[v] = .some(nil) } else { values.append(v) }
            token = ""
        }
        for ch in body {
            switch ch {
            case "(": flushToken(); depth += 1; values = []
            case ")": flushToken(); depth -= 1; if let c = current { out[c] = .some(values) }
            case " ", "\t", "\n": flushToken()
            default: token.append(ch)
            }
        }
        flushToken()
        return out
    }
}
