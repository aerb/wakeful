// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wakeful",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Wakeful", targets: ["Wakeful"]),
        .executable(name: "wakeful-watchdog", targets: ["WakefulWatchdog"]),
    ],
    targets: [
        .target(name: "WakefulCore"),
        .executableTarget(name: "Wakeful", dependencies: ["WakefulCore"]),
        .executableTarget(name: "WakefulWatchdog", dependencies: ["WakefulCore"]),
        .testTarget(name: "WakefulCoreTests", dependencies: ["WakefulCore"]),
    ]
)
