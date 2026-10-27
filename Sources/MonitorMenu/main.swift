// Created: 2026-10-19 19:23 -05:00 · Edited: 2026-10-27 09:54 -05:00
import AppKit

// MonitorMenu — the menu bar app. Thin: builds menus from MonitorCore state and forwards clicks.
_ = MonitorStore.launched   // start the launch clock for the log's timing lines (C4-T3)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
