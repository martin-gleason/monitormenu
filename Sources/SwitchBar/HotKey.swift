import Carbon.HIToolbox
import Foundation

/// A global hotkey via Carbon's RegisterEventHotKey — no Accessibility permission needed (D9).
/// Default ⌃⌥⌘I. Override: `defaults write dev.marty.SwitchBar hotkey "ctrl+opt+cmd+i"`.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    static let defaultSpec = "ctrl+opt+cmd+i"

    init?(spec: String, action: @escaping () -> Void) {
        self.action = action
        guard let (keyCode, modifiers) = HotKey.parse(spec) else { return nil }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: 0x5357_4248, id: 1)  // 'SWBH'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { return nil }
    }

    deinit {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "space": 49, "`": 50,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// "ctrl+opt+cmd+i" → (keyCode, Carbon modifier mask). Accepts ctrl/control, opt/option/alt, cmd/command, shift.
    static func parse(_ spec: String) -> (UInt32, UInt32)? {
        var mods: UInt32 = 0
        var key: UInt32?
        for raw in spec.lowercased().split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " }) {
            switch raw {
            case "ctrl", "control", "⌃": mods |= UInt32(controlKey)
            case "opt", "option", "alt", "⌥": mods |= UInt32(optionKey)
            case "cmd", "command", "⌘": mods |= UInt32(cmdKey)
            case "shift", "⇧": mods |= UInt32(shiftKey)
            default: key = keyCodes[String(raw)]
            }
        }
        guard let k = key, mods != 0 else { return nil }
        return (k, mods)
    }

    static func describe(_ spec: String) -> String {
        var out = ""
        for raw in spec.lowercased().split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " }) {
            switch raw {
            case "ctrl", "control": out += "⌃"
            case "opt", "option", "alt": out += "⌥"
            case "shift": out += "⇧"
            case "cmd", "command": out += "⌘"
            default: out += raw.uppercased()
            }
        }
        return out
    }
}
