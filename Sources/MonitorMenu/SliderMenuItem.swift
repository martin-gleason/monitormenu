import AppKit

/// A menu row with a label and a slider (brightness, contrast). Dragging writes after a short pause.
final class SliderMenuItem: NSMenuItem {
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var pending: DispatchWorkItem?
    var onChange: ((UInt16) -> Void)?

    init(title: String) {
        super.init(title: title, action: nil, keyEquivalent: "")
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        label.stringValue = title
        label.font = .menuFont(ofSize: 13)
        label.frame = NSRect(x: 22, y: 5, width: 72, height: 17)
        slider.frame = NSRect(x: 96, y: 3, width: 118, height: 20)
        slider.target = self; slider.action = #selector(moved(_:))
        slider.isContinuous = true
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.alignment = .right
        value.frame = NSRect(x: 218, y: 5, width: 34, height: 17)
        v.addSubview(label); v.addSubview(slider); v.addSubview(value)
        view = v
    }
    required init(coder: NSCoder) { fatalError() }

    func set(current: UInt16, max: UInt16, enabled: Bool) {
        slider.maxValue = Double(Swift.max(1, max))
        slider.doubleValue = Double(current)
        slider.isEnabled = enabled
        value.stringValue = enabled ? "\(current)" : "—"
    }

    @objc private func moved(_ sender: NSSlider) {
        let v = UInt16(sender.doubleValue.rounded())
        value.stringValue = "\(v)"
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange?(v) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }
}
