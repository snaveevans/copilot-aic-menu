// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CopilotAICMenu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CopilotAICMenu", targets: ["CopilotAICMenu"])],
    targets: [
        .target(name: "AICCore"),
        .executableTarget(name: "CopilotAICMenu", dependencies: ["AICCore"]),
        .executableTarget(name: "AICCoreChecks", dependencies: ["AICCore"]),
    ]
)
