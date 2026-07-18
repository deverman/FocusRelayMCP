// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FocusRelayMCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "focusrelay", targets: ["FocusRelayCLI"]),
        .executable(name: "focusrelay-dev", targets: ["FocusRelayDevCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "FocusRelayVersion"
        ),
        .target(
            name: "OmniFocusCore"
        ),
        .target(
            name: "FocusRelayOutput",
            dependencies: ["OmniFocusCore"]
        ),
        .target(
            name: "FocusRelayServer",
            dependencies: [
                "OmniFocusCore",
                "OmniFocusAutomation",
                "FocusRelayOutput",
                "FocusRelayVersion",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "OmniFocusAutomation",
            dependencies: ["OmniFocusCore"]
        ),
        .executableTarget(
            name: "FocusRelayCLI",
            dependencies: [
                "OmniFocusCore",
                "OmniFocusAutomation",
                "FocusRelayOutput",
                "FocusRelayServer",
                "FocusRelayVersion",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "FocusRelayDevCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .executableTarget(
            name: "FocusRelayDevCLI",
            dependencies: [
                "FocusRelayDevCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "OmniFocusCoreTests",
            dependencies: [
                "OmniFocusCore"
            ]
        ),
        .testTarget(
            name: "OmniFocusIntegrationTests",
            dependencies: [
                "OmniFocusAutomation",
                "OmniFocusCore",
                "FocusRelayVersion"
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .testTarget(
            name: "FocusRelayCLITests",
            dependencies: [
                "FocusRelayCLI",
                "FocusRelayVersion"
            ]
        ),
        .testTarget(
            name: "FocusRelayServerTests",
            dependencies: [
                "FocusRelayServer",
                "FocusRelayVersion"
            ]
        ),
        .testTarget(
            name: "FocusRelayDevCoreTests",
            dependencies: ["FocusRelayDevCore"]
        )
    ]
)
