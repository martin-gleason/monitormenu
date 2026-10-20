import AppKit
import SwitchCore

/// FR6: a compact panel listing every monitor's inputs. Press the number, or Esc to dismiss.
final class SwitcherPanel: NSPanel {
    private let content = SwitcherView()
    var onPick: ((CGDirectDisplayID, UInt8) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled, .nonactivatingPanel, .hudWindow, .utilityWindow], backing: .buffered, defer: true)
        title = "Switch Input"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
        content.onPick = { [weak self] id, code in self?.onPick?(id, code); self?.close() }
        content.onCancel = { [weak self] in self?.close() }
    }

    func show(states: [MonitorState]) {
        content.states = states
        let h = content.preferredHeight
        setContentSize(NSSize(width: 320, height: h))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - 160, y: f.midY - h / 2 + 80))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(content)
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

final class SwitcherView: NSView {
    var states: [MonitorState] = [] { didSet { rebuild() } }
    var onPick: ((CGDirectDisplayID, UInt8) -> Void)?
    var onCancel: (() -> Void)?
    private var rows: [(id: CGDirectDisplayID, code: UInt8)] = []
    private(set) var preferredHeight: CGFloat = 60

    override var acceptsFirstResponder: Bool { true }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        rows = []
        var y: CGFloat = 12
        var items: [(NSView, CGFloat)] = []
        var n = 0
        for s in states.reversed() {
            var lines: [(NSView, CGFloat)] = []
            for code in s.inputs {
                n += 1
                let active = s.currentInput == code
                let b = NSButton(title: "\(n)   \(VCP.label(code: VCP.inputSource, value: code))\(active ? "   ●" : "")", target: self, action: #selector(click(_:)))
                b.bezelStyle = .inline; b.isBordered = false; b.alignment = .left
                b.font = .systemFont(ofSize: 13, weight: active ? .semibold : .regular)
                b.tag = rows.count; b.contentTintColor = .labelColor
                rows.append((s.id, code))
                lines.append((b, 24))
            }
            let header = NSTextField(labelWithString: s.name)
            header.font = .systemFont(ofSize: 11, weight: .semibold); header.textColor = .secondaryLabelColor
            lines.append((header, 20))
            items.append(contentsOf: lines)
        }
        if rows.isEmpty { items.append((NSTextField(labelWithString: "No DDC-capable monitor connected"), 24)) }
        let hint = NSTextField(labelWithString: "Press a number · Esc to close"); hint.font = .systemFont(ofSize: 10); hint.textColor = .tertiaryLabelColor
        var all: [(NSView, CGFloat)] = [(hint, 18)]
        all.append(contentsOf: items)
        for (v, h) in all { v.frame = NSRect(x: 16, y: y, width: 288, height: h - 4); addSubview(v); y += h }
        preferredHeight = y + 8
        // Number the rows top-down.
        var k = 1
        for v in subviews.reversed() where v is NSButton {
            let b = v as! NSButton
            let title = b.title.drop { $0 != " " }
            b.title = "\(k)\(title)"; k += 1
        }
    }

    @objc private func click(_ sender: NSButton) {
        guard sender.tag < rows.count else { return }
        let r = rows[sender.tag]; onPick?(r.id, r.code)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }  // Esc
        guard let ch = event.charactersIgnoringModifiers, let n = Int(ch), n >= 1 else { super.keyDown(with: event); return }
        // Visible numbering is top-down; rows were built bottom-up.
        let ordered = Array(rows.reversed())
        guard n <= ordered.count else { return }
        onPick?(ordered[n - 1].id, ordered[n - 1].code)
    }
}
