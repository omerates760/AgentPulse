// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "AgentPulse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentPulse",
            path: "Sources/AgentPulse",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "AgentPulseBridge",
            path: "Sources/AgentPulseBridge"
        ),
    ]
)
