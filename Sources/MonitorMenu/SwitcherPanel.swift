import AppKit
import MonitorCore

/// FR6: a compact panel listing every monitor's inputs. Press the number, or Esc to dismiss.
final class SwitcherPanel: NSPanel {
    private let content = SwitcherView()
    var onPick: ((String, UInt8) -> Void)?

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

/// Rows are laid out top-down in monitor order, then input order; row k (1-based) is what key k picks.
final class SwitcherView: NSView {
    var states: [MonitorState] = [] { didSet { rebuild() } }
    var onPick: ((String, UInt8) -> Void)?
    var onCancel: (() -> Void)?
    private var rows: [(id: String, code: UInt8)] = []
    private(set) var preferredHeight: CGFloat = 60

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // y grows downward, so "top-down" is literal

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        rows = []
        var y: CGFloat = 10
        func place(_ v: NSView, height: CGFloat) { v.frame = NSRect(x: 16, y: y, width: 288, height: height - 4); addSubview(v); y += height }
        let names = MonitorNames()
        for s in states {
            let shown = names.displayName(for: s.identity)
            let header = NSTextField(labelWithString: shown == s.name ? s.name : "\(shown)  ·  \(s.name)")
            header.font = .systemFont(ofSize: 11, weight: .semibold); header.textColor = .secondaryLabelColor
            place(header, height: 20)
            for code in s.inputs {
                rows.append((s.id, code))
                let active = s.currentInput == code
                let b = NSButton(title: "\(rows.count)   \(VCP.label(code: VCP.inputSource, value: code))\(active ? "   ●" : "")", target: self, action: #selector(click(_:)))
                b.bezelStyle = .inline; b.isBordered = false; b.alignment = .left
                b.font = .systemFont(ofSize: 13, weight: active ? .semibold : .regular)
                b.tag = rows.count - 1; b.contentTintColor = .labelColor
                place(b, height: 24)
            }
        }
        if rows.isEmpty { place(NSTextField(labelWithString: "No DDC-capable monitor connected"), height: 24) }
        let hint = NSTextField(labelWithString: "Press a number · Esc to close"); hint.font = .systemFont(ofSize: 10); hint.textColor = .tertiaryLabelColor
        place(hint, height: 18)
        preferredHeight = y + 6
    }

    @objc private func click(_ sender: NSButton) {
        guard sender.tag < rows.count else { return }
        let r = rows[sender.tag]; onPick?(r.id, r.code)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }  // Esc
        guard let ch = event.charactersIgnoringModifiers, let n = Int(ch), n >= 1, n <= rows.count else { super.keyDown(with: event); return }
        onPick?(rows[n - 1].id, rows[n - 1].code)
    }
}
