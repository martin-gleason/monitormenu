import AppKit
import SwitchCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let store = MonitorStore()
    private var sliders: [String: SliderMenuItem] = [:]   // "\(id):brightness"
    private var checkItems: [String: NSMenuItem] = [:]    // "\(id):input:\(code)", "\(id):pip:\(code)"
    private var menuOpen = false
    private var rebuildWhenClosed = false
    private var hotKey: HotKey?
    private let switcher = SwitcherPanel()
    private var hotKeySpec: String { UserDefaults.standard.string(forKey: "hotkey") ?? HotKey.defaultSpec }

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
        Actions.shared = Actions(store: store)
        Actions.shared.openSwitcher = { [weak self] in self?.openSwitcher() }
        switcher.onPick = { [weak self] id, code in
            self?.store.perform(on: id, retrainsLink: true, { try $0.setInput(code) }, completion: self?.report)
        }
        // FR9: the default hotkey is live on first launch (D9).
        hotKey = HotKey(spec: hotKeySpec) { [weak self] in self?.openSwitcher() }
        if hotKey == nil { NSLog("SwitchBar: hotkey \"%@\" could not be registered", hotKeySpec) }
        // Screen changes (a monitor retraining its link, plug and unplug) → look again.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.store.scheduleRediscover()
        }
        store.discover()
        rebuild()
    }

    /// FR7: switchbar:// URLs from Alfred, Raycast, Shortcuts "Open URL", or a terminal.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                do { NSLog("SwitchBar: %@", try await Actions.shared.handle(url: url)) }
                catch { self.report(error.localizedDescription) }
            }
        }
    }

    @objc func openSwitcher() {
        store.refresh()
        switcher.show(states: store.states)
    }

    // FR8: re-read on open. The menu shows the cached state immediately and updates in place.
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; store.refresh() }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        if rebuildWhenClosed { rebuildWhenClosed = false; rebuild() }
    }

    /// While the menu is open, tearing items down would kill a slider mid-drag; update values in place
    /// and defer structural changes (a monitor appearing or disappearing) until it closes.
    private func rebuild() {
        if menuOpen {
            let structureChanged = store.states.count != sliders.count / 2 && !(store.states.isEmpty && sliders.isEmpty)
            if structureChanged { rebuildWhenClosed = true }
            updateInPlace()
            return
        }
        rebuildNow()
    }

    private func updateInPlace() {
        for s in store.states {
            sliders["\(s.id):brightness"]?.set(current: s.brightness?.current ?? 0, max: s.brightness?.max ?? 100, enabled: s.brightness != nil)
            sliders["\(s.id):contrast"]?.set(current: s.contrast?.current ?? 0, max: s.contrast?.max ?? 100, enabled: s.contrast != nil)
            for code in s.inputs { checkItems["\(s.id):input:\(code)"]?.state = s.currentInput == code ? .on : .off }
            for mode in s.pipModes { checkItems["\(s.id):pip:\(mode)"]?.state = s.pipMode == mode ? .on : .off }
        }
    }

    private func rebuildNow() {
        menu.removeAllItems()
        sliders.removeAll()
        checkItems.removeAll()
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
                checkItems["\(s.id):input:\(code)"] = i
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
                    checkItems["\(s.id):pip:\(mode)"] = i
                    sub.addItem(i)
                }
                if s.monitor.hasPiPSource, !s.inputs.isEmpty {
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
        let sw = NSMenuItem(title: "Input Switcher…", action: #selector(openSwitcher), keyEquivalent: ""); sw.target = self
        sw.toolTip = "Global hotkey \(HotKey.describe(hotKeySpec))"
        menu.addItem(sw)
        let hint = NSMenuItem(title: "Hotkey: \(HotKey.describe(hotKeySpec))", action: nil, keyEquivalent: ""); hint.isEnabled = false; hint.indentationLevel = 1
        menu.addItem(hint)
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

    final class Action: NSObject { let id: String; let code: UInt8; init(id: String, code: UInt8) { self.id = id; self.code = code } }

    @objc private func pickInput(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, retrainsLink: true, { try $0.setInput(a.code) }, completion: report)
    }
    @objc private func pickPiP(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        store.perform(on: a.id, retrainsLink: true, { try $0.setPiPMode(a.code) }, completion: report)
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
