// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwitchBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwitchBar", targets: ["SwitchBar"]),
        .executable(name: "switchctl", targets: ["switchctl"]),
    ],
    targets: [
        // Declarations for IOKit's unexported-but-linkable IOAVService I2C calls (D1).
        .target(name: "CDDC", path: "Sources/CDDC",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        // Everything that talks to a monitor. No AppKit (NFR7), so it can be tested headless.
        .target(name: "SwitchCore", dependencies: ["CDDC"], path: "Sources/SwitchCore",
                linkerSettings: [.linkedFramework("CoreGraphics")]),
        // The menu bar app. Thin: builds menus from SwitchCore and forwards clicks.
        .executableTarget(name: "SwitchBar", dependencies: ["SwitchCore"], path: "Sources/SwitchBar"),
        // Command-line entry point (FR7). Same actions as the menu.
        .executableTarget(name: "switchctl", dependencies: ["SwitchCore"], path: "Sources/switchctl"),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"], path: "Tests/SwitchCoreTests"),
    ]
)
