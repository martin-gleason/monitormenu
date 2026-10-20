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
//
// `get <hex code>` reads any code for diagnosis. There is deliberately no raw `set <code> <value>`:
// writes are limited to the spec's FR2–FR5 controls (review K2, 2026-10-19).
//
// --display X matches the monitor's name (substring, case-insensitive) or its CoreGraphics id.

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

func pick() -> Monitor {
    guard let sel = displaySel else { return monitors[0] }
    if let m = monitors.first(where: { $0.name.lowercased().contains(sel.lowercased()) || "\($0.identity.displayID ?? 0)" == sel }) { return m }
    fail(DDCError.noSuchMonitor(sel).description)
}

func load(_ m: Monitor) -> Capabilities {
    if let c = m.capabilities { return c }
    do { return try m.loadCapabilities() } catch { fail("\(m.name): could not read capabilities: \(error)") }
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
            rows.append(["name": m.name, "displayID": m.identity.displayID ?? 0, "serial": m.identity.alphanumericSerial ?? "",
                         "model": caps.model ?? "", "inputs": inputs,
                         "input": input.map(hex) ?? "", "brightness": b?.current ?? -1, "contrast": c?.current ?? -1,
                         "pip": m.hasPiP, "pipModes": m.pipModes().map { ["code": hex($0), "name": VCP.label(code: VCP.pipMode, value: $0)] }])
        } else {
            print("\(m.name)  [display \(m.identity.displayID ?? 0), serial \(m.identity.alphanumericSerial ?? "?"), model \(caps.model ?? "?")]")
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
    } catch { fail("\(m.name): \(error)") }

case "set":
    let m = pick(); _ = load(m)
    guard args.count >= 3 else { fail("set what to what?") }
    do {
        switch args[1] {
        case "input":
            guard let code = VCP.inputCode(from: args[2]) else { fail("unknown input \(args[2])") }
            try m.setInput(code); print("\(m.name): input → \(VCP.label(code: VCP.inputSource, value: code))")
        case "brightness": guard let v = UInt16(args[2]) else { fail("number 0–100") }; try m.setBrightness(v); print("\(m.name): brightness → \(v)")
        case "contrast": guard let v = UInt16(args[2]) else { fail("number 0–100") }; try m.setContrast(v); print("\(m.name): contrast → \(v)")
        case "power":
            let v: UInt8 = args[2] == "standby" ? 0x04 : args[2] == "on" ? 0x01 : args[2] == "off" ? 0x05 : UInt8(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
            try m.setPower(v); print("\(m.name): power → \(VCP.label(code: VCP.powerMode, value: v))")
        case "pip":
            guard let v = VCP.pipCode(from: args[2]) else { fail("unknown pip mode \(args[2]) — off, small, large, split, or 0xNN") }
            try m.setPiPMode(v); print("\(m.name): pip → \(VCP.label(code: VCP.pipMode, value: v))")
        case "pip-source":
            guard let code = VCP.inputCode(from: args[2]) else { fail("unknown input \(args[2])") }
            try m.setPiPSource(code); print("\(m.name): pip source → \(VCP.label(code: VCP.inputSource, value: code))")
        default: fail("set input|brightness|contrast|power|pip|pip-source — raw codes are read-only (`get 0xNN`)")
        }
    } catch { fail("\(m.name): \(error)") }

case "probe":
    let m = pick(); _ = load(m)
    var ok = 0, fails = 0; var ms: [Double] = []
    for _ in 0..<count {
        let t = Date()
        if (try? m.brightness()) != nil { ok += 1; ms.append(Date().timeIntervalSince(t) * 1000) } else { fails += 1 }
    }
    let avg = ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
    print("\(m.name): \(ok)/\(count) reads succeeded, \(fails) failed, mean \(String(format: "%.0f", avg)) ms per read (\(m.link.timing.attempts) attempts max each)")

default:
    fail("usage: monitorctl list|capabilities|get|set|probe  (see source header)")
}
