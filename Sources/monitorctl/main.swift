import Foundation
import MonitorCore

// monitorctl — the command-line entry point (FR7). Same MonitorCore actions as the menu.
//
//   monitorctl list [--json]              every DDC-capable monitor with inputs and current values
//   monitorctl capabilities [--display X] the raw capabilities string
//   monitorctl get <brightness|contrast|input|power|pip> [--display X]
//   monitorctl set input <hdmi1|hdmi2|dp1|dp2|usbc|0xNN> [--display X]
//   monitorctl set <brightness|contrast> <0-100> [--display X]
//   monitorctl set power <standby|on|0xNN> [--display X]
//   monitorctl set pip <off|small|large|split|0xNN> [--display X]    monitorctl set pip-source <input> [--display X]
//   monitorctl probe [--display X] [--count N]       RR2: read reliability over N reads
//   monitorctl rename "<name>" [--display X]         FR10: name a monitor; --clear removes the name
//
// `get <hex code>` reads any code for diagnosis. There is deliberately no raw `set <code> <value>`:
// writes are limited to the spec's FR2–FR5 controls (review K2, 2026-10-19).
//
// --display X picks a monitor: exact user name, serial, CoreGraphics id or model name first, then a
// case-insensitive substring of the user name, then of the model name. A selector that fits two monitors is
// refused rather than guessed.

var args = Array(CommandLine.arguments.dropFirst())
func takeOption(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...i + 1); return v
}
func takeFlag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}
func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

let displaySel = takeOption("--display")
let json = takeFlag("--json")
let count = max(1, min(10_000, Int(takeOption("--count") ?? "") ?? 100))
let verb = args.first ?? "list"

let monitors = MonitorDiscovery.discover()
if monitors.isEmpty { fail("no external monitor with a DDC channel was found") }

let names = MonitorNames()
func shown(_ m: Monitor) -> String { let n = names.displayName(for: m.identity); return n == m.name ? m.name : "\(n) (\(m.name))" }
func pick() -> Monitor {
    // FR10: the user's name wins, then the monitor's own name, serial or display id.
    do {
        if let id = try names.match(displaySel ?? "", in: monitors.map { $0.identity }), let m = monitors.first(where: { $0.identity.key == id.key }) { return m }
    } catch { fail("\(error)") }
    fail(DDCError.noSuchMonitor(displaySel ?? "").description)
}

func load(_ m: Monitor) -> Capabilities {
    if let c = m.capabilities { return c }
    do { return try m.loadCapabilities() } catch { fail("\(shown(m)): could not read capabilities: \(error)") }
}

func hex(_ v: UInt8) -> String { String(format: "0x%02X", v) }

switch verb {
case "list":
    var rows: [[String: Any]] = []
    for m in monitors {
        let caps = load(m)
        let input = try? m.currentInput()
        let b = try? m.brightness(), c = try? m.contrast()
        let inputs = m.inputs().map { ["code": hex($0), "name": VCP.label(code: VCP.inputSource, value: $0), "active": input == $0] }
        if json {
            rows.append(["name": names.displayName(for: m.identity), "modelName": m.name, "displayID": m.identity.displayID ?? 0, "serial": m.identity.alphanumericSerial ?? "",
                         "model": caps.model ?? "", "inputs": inputs,
                         "input": input.map(hex) ?? "", "brightness": b?.current ?? -1, "contrast": c?.current ?? -1,
                         "pip": m.hasPiP, "pipModes": m.pipModes().map { ["code": hex($0), "name": VCP.label(code: VCP.pipMode, value: $0)] }])
        } else {
            print("\(shown(m))  [display \(m.identity.displayID ?? 0), serial \(m.identity.alphanumericSerial ?? "?"), model \(caps.model ?? "?")]")
            print("  inputs:     " + m.inputs().map { ($0 == input ? "● " : "○ ") + VCP.label(code: VCP.inputSource, value: $0) + " (\(hex($0)))" }.joined(separator: "  "))
            print("  brightness: \(b.map { "\($0.current)/\($0.max)" } ?? "?")   contrast: \(c.map { "\($0.current)/\($0.max)" } ?? "?")")
            if m.hasPiP { print("  pip modes:  " + m.pipModes().map { VCP.label(code: VCP.pipMode, value: $0) + " (\(hex($0)))" }.joined(separator: "  ")) }
            print("  power:      " + m.powerModes().map { VCP.label(code: VCP.powerMode, value: $0) + " (\(hex($0)))" }.joined(separator: "  "))
        }
    }
    if json, let d = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: d, as: UTF8.self)) }

case "capabilities":
    let m = pick(); print(load(m).raw)

case "get":
    let m = pick(); _ = load(m)
    guard args.count >= 2 else { fail("get what?") }
    do {
        switch args[1] {
        case "brightness": let r = try m.brightness(); print(r.current)
        case "contrast": let r = try m.contrast(); print(r.current)
        case "input": let i = try m.currentInput(); print("\(VCP.label(code: VCP.inputSource, value: i)) (\(hex(i)))")
        case "power": let r = try m.get(VCP.powerMode); print(VCP.label(code: VCP.powerMode, value: UInt8(r.current & 0xFF)))
        case "pip": let v = try m.currentPiPMode(); print("\(VCP.label(code: VCP.pipMode, value: v)) (\(hex(v)))")
        default:
            guard let code = UInt8(args[1].replacingOccurrences(of: "0x", with: ""), radix: 16) else { fail("unknown property \(args[1])") }
            let r = try m.get(code); print("current \(r.current) max \(r.maximum)")
        }
    } catch { fail("\(shown(m)): \(error)") }

case "set":
    let m = pick(); _ = load(m)
    guard args.count >= 3 else { fail("set what to what?") }
    do {
        switch args[1] {
        case "input":
            guard let code = VCP.inputCode(from: args[2]) else { fail("unknown input \(args[2])") }
            try m.setInput(code); print("\(shown(m)): input → \(VCP.label(code: VCP.inputSource, value: code))")
        case "brightness": guard let v = UInt16(args[2]), v <= 100 else { fail("number 0–100") }; try m.setBrightness(v); print("\(shown(m)): brightness → \(v)")
        case "contrast": guard let v = UInt16(args[2]), v <= 100 else { fail("number 0–100") }; try m.setContrast(v); print("\(shown(m)): contrast → \(v)")
        case "power":
            let v: UInt8 = args[2] == "standby" ? 0x04 : args[2] == "on" ? 0x01 : args[2] == "off" ? 0x05 : UInt8(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
            try m.setPower(v); print("\(shown(m)): power → \(VCP.label(code: VCP.powerMode, value: v))")
        case "pip":
            guard let v = VCP.pipCode(from: args[2]) else { fail("unknown pip mode \(args[2]) — off, small, large, split, or 0xNN") }
            try m.setPiPMode(v); print("\(shown(m)): pip → \(VCP.label(code: VCP.pipMode, value: v))")
        case "pip-source":
            guard let code = VCP.inputCode(from: args[2]) else { fail("unknown input \(args[2])") }
            try m.setPiPSource(code); print("\(shown(m)): pip source → \(VCP.label(code: VCP.inputSource, value: code))")
        default: fail("set input|brightness|contrast|power|pip|pip-source — raw codes are read-only (`get 0xNN`)")
        }
    } catch { fail("\(shown(m)): \(error)") }

case "rename":
    let m = pick()
    // `rename` alone is a usage error, not a clear; a dangling flag is never a name (review F2 #2, #3).
    let clear = takeFlag("--clear")
    let newName = args.count > 1 ? args[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    if newName.hasPrefix("--") { fail("rename: \"\(newName)\" looks like a flag, not a name (--display needs a value)") }
    if !clear && args.count < 2 { fail("usage: monitorctl rename \"<name>\" [--display X]   or   monitorctl rename --clear [--display X]") }
    if clear || newName.isEmpty { names.clear(for: m.identity); print("\(m.name): name cleared") }
    else { names.set(newName, for: m.identity); print("\(m.name): named \"\(names.displayName(for: m.identity))\"") }

case "probe":
    let m = pick(); _ = load(m)
    var ok = 0, fails = 0; var ms: [Double] = []
    for _ in 0..<count {
        let t = Date()
        if (try? m.brightness()) != nil { ok += 1; ms.append(Date().timeIntervalSince(t) * 1000) } else { fails += 1 }
    }
    let avg = ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
    print("\(shown(m)): \(ok)/\(count) reads succeeded, \(fails) failed, mean \(String(format: "%.0f", avg)) ms per read (\(m.link.timing.attempts) attempts max each)")

default:
    fail("usage: monitorctl list|capabilities|get|set|rename|probe  (see source header)")
}
