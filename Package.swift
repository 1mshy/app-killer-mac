// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Killer",
    platforms: [.macOS(.v26)],
    products: [.library(name: "KillerCore", targets: ["KillerCore"])],
    targets: [
        .target(name: "CProcess", publicHeadersPath: "include"),
        .target(name: "KillerCore", dependencies: ["CProcess"]),
        .testTarget(name: "KillerCoreTests", dependencies: ["KillerCore"])
    ]
)
