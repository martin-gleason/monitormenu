// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MonitorMenu", targets: ["MonitorMenu"]),
        .executable(name: "monitorctl", targets: ["monitorctl"]),
    ],
    targets: [
        // Declarations for IOKit's unexported-but-linkable IOAVService I2C calls (D1).
        .target(name: "CDDC", path: "Sources/CDDC",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        // Everything that talks to a monitor. No AppKit (NFR7), so it can be tested headless.
        .target(name: "MonitorCore", dependencies: ["CDDC"], path: "Sources/MonitorCore",
                linkerSettings: [.linkedFramework("CoreGraphics")]),
        // The menu bar app. Thin: builds menus from MonitorCore and forwards clicks.
        .executableTarget(name: "MonitorMenu", dependencies: ["MonitorCore"], path: "Sources/MonitorMenu"),
        // Command-line entry point (FR7). Same actions as the menu.
        .executableTarget(name: "monitorctl", dependencies: ["MonitorCore"], path: "Sources/monitorctl"),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests"),
    ]
)
