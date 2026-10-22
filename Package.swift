// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ChromeProfileBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (config, title matching, placement) so it can be unit tested.
        .target(name: "ProfileBarCore"),
        .executableTarget(name: "ChromeProfileBar", dependencies: ["ProfileBarCore"]),
        .testTarget(name: "ProfileBarCoreTests", dependencies: ["ProfileBarCore"]),
    ]
)
