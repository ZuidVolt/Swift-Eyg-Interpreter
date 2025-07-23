// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftEygInterpreter",
    platforms: [.macOS(.v11)],
    targets: [
        .target(name: "EygInterpreter"),
        .executableTarget(
            name: "EygRunnerTest",
            dependencies: ["EygInterpreter"],
            resources: [.copy("examples")]
        ),
        .executableTarget(
            name: "EygRunner",
            dependencies: ["EygInterpreter"],
        ),
    ]
)
