// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyWindowManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyWindowManager", targets: ["MyWindowManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MyWindowManager",
            dependencies: ["HotKey"],
            path: "Sources/MyWindowManager"
        ),
        .testTarget(
            name: "MyWindowManagerTests",
            dependencies: ["MyWindowManager"],
            path: "Tests/MyWindowManagerTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
