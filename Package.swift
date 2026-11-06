// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StatusX",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StatusX",
            path: "Sources/StatusX"
        )
    ]
)
