import AppKit

// MonitorMenu — the menu bar app. Thin: builds menus from MonitorCore state and forwards clicks.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
