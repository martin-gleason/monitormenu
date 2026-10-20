import AppKit
import SwitchCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let store = MonitorStore()
    private var sliders: [String: SliderMenuItem] = [:]   // "\(id):brightness"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "display", accessibilityDescription: "SwitchBar")
            b.image?.isTemplate = true
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        store.onChange = { [weak self] in self?.rebuild() }
        store.discover()
        rebuild()
    }

    // FR8: re-read on open. The menu shows the cached state immediately and updates in place.
    func menuWillOpen(_ menu: NSMenu) { store.refresh() }

    private func rebuild() {
        menu.removeAllItems()
        sliders.removeAll()
        if store.states.isEmpty {
            let i = NSMenuItem(title: "No DDC-capable monitor found", action: nil, keyEquivalent: ""); i.isEnabled = false
            menu.addItem(i)
        }
        for s in store.states {
            let header = NSMenuItem(title: s.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(string: s.name, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            menu.addItem(header)

            for code in s.inputs {   // FR2
                let i = NSMenuItem(title: VCP.label(code: VCP.inputSource, value: code), action: #selector(pickInput(_:)), keyEquivalent: "")
                i.target = self; i.indentationLevel = 1
                i.representedObject = Action(id: s.id, code: code)
                i.state = s.currentInput == code ? .on : .off
                menu.addItem(i)
            }

            if s.monitor.capabilities?.advertises(VCP.brightness) == true {   // FR3
                let b = slider(for: s, key: "brightness", title: "Brightness", value: s.brightness) { [weak self] v in
                    self?.store.perform(on: s.id, { try $0.setBrightness(v) }, completion: self?.report)
                }
                menu.addItem(b)
            }
            if s.monitor.capabilities?.advertises(VCP.contrast) == true {
                let c = slider(for: s, key: "contrast", title: "Contrast", value: s.contrast) { [weak self] v in
                    self?.store.perform(on: s.id, { try $0.setContrast(v) }, completion: self?.report)
                }
                menu.addItem(c)
            }

            if s.monitor.hasPiP {   // FR4
                let pip = NSMenuItem(title: "Picture-in-Picture", action: nil, keyEquivalent: ""); pip.indentationLevel = 1
                let sub = NSMenu(); sub.autoenablesItems = false
                for mode in s.pipModes {
                    let i = NSMenuItem(title: VCP.label(code: VCP.pipMode, value: mode), action: #selector(pickPiP(_:)), keyEquivalent: "")
                    i.target = self; i.representedObject = Action(id: s.id, code: mode); i.state = s.pipMode == mode ? .on : .off
                    sub.addItem(i)
                }
                if s.monitor.capabilities?.advertises(VCP.pipSource) == true, !s.inputs.isEmpty {
                    sub.addItem(.separator())
                    let src = NSMenuItem(title: "Second Source", action: nil, keyEquivalent: "")
                    let srcMenu = NSMenu(); srcMenu.autoenablesItems = false
                    for code in s.inputs {
                        let i = NSMenuItem(title: VCP.label(code: VCP.inputSource, value: code), action: #selector(pickPiPSource(_:)), keyEquivalent: "")
                        i.target = self; i.representedObject = Action(id: s.id, code: code)
                        srcMenu.addItem(i)
                    }
                    src.submenu = srcMenu; sub.addItem(src)
                }
                pip.submenu = sub
                menu.addItem(pip)
            }

            if s.powerModes.contains(0x04) || s.powerModes.contains(0x05) {   // FR5
                let code: UInt8 = s.powerModes.contains(0x04) ? 0x04 : 0x05
                let i = NSMenuItem(title: "Put Display to Sleep", action: #selector(pickPower(_:)), keyEquivalent: "")
                i.target = self; i.indentationLevel = 1; i.representedObject = Action(id: s.id, code: code)
                menu.addItem(i)
            }
            if let e = s.lastError {   // NFR4: failures are a greyed line, never a dialog
                let i = NSMenuItem(title: "Not responding: \(e)", action: nil, keyEquivalent: ""); i.isEnabled = false; i.indentationLevel = 1
                menu.addItem(i)
            }
            menu.addItem(.separator())
        }
        let refresh = NSMenuItem(title: "Rescan Displays", action: #selector(rescan), keyEquivalent: "r"); refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit SwitchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func slider(for s: MonitorState, key: String, title: String, value: (current: UInt16, max: UInt16)?, onChange: @escaping (UInt16) -> Void) -> SliderMenuItem {
        let item = SliderMenuItem(title: title)
        item.set(current: value?.current ?? 0, max: value?.max ?? 100, enabled: value != nil)
        item.onChange = onChange
        sliders["\(s.id):\(key)"] = item
        return item
    }

    final class Action: NSObject { let id: CGDirectDisplayID; let code: UInt8; init(id: CGDirectDisplayID, code: UInt8) { self.id = id; self.code = code } }

    @objc private func pickInput(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, { try $0.setInput(a.code) }, completion: report)
    }
    @objc private func pickPiP(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, { try $0.setPiPMode(a.code) }, completion: report)
    }
    @objc private func pickPiPSource(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, { try $0.setPiPSource(a.code) }, completion: report)
    }
    @objc private func pickPower(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, { try $0.setPower(a.code) }, completion: report)
    }
    @objc private func rescan() { store.discover() }

    /// NFR4: a failed write is reported in the menu bar title for a moment, never as a modal.
    private func report(_ error: String?) {
        guard let error, let b = statusItem.button else { return }
        NSLog("SwitchBar: %@", error)
        b.image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark", accessibilityDescription: error)
        b.toolTip = error
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "SwitchBar")
            self?.statusItem.button?.toolTip = nil
        }
    }
}
