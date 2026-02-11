// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FocusRelayMCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "focusrelay", targets: ["FocusRelayCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
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
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "OmniFocusAutomation",
            dependencies: ["OmniFocusCore"],
            linkerSettings: [
                .linkedFramework("OSAKit")
            ]
        ),
        .executableTarget(
            name: "FocusRelayCLI",
            dependencies: [
                "OmniFocusCore",
                "OmniFocusAutomation",
                "FocusRelayOutput",
                "FocusRelayServer",
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
                "OmniFocusCore"
            ]
        ),
        .testTarget(
            name: "FocusRelayCLITests",
            dependencies: [
                "FocusRelayCLI"
            ]
        ),
        .testTarget(
            name: "FocusRelayServerTests",
            dependencies: [
                "FocusRelayServer"
            ]
        )
    ]
)
