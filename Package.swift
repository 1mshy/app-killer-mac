// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Killer",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Killer", targets: ["Killer"]),
        .executable(name: "KillerPrivileged", targets: ["KillerPrivileged"])
    ],
    targets: [
        .target(name: "CProcess", publicHeadersPath: "include"),
        .target(name: "KillerCore", dependencies: ["CProcess"]),
        .executableTarget(name: "Killer", dependencies: ["KillerCore"]),
        .executableTarget(name: "KillerPrivileged", dependencies: ["KillerCore"]),
        .testTarget(name: "KillerCoreTests", dependencies: ["KillerCore"]),
        .testTarget(name: "KillerAppTests", dependencies: ["Killer", "KillerCore"])
    ]
)
