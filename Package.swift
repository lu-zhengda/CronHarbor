// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CronHarbor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CronHarborCore", targets: ["CronHarborCore"]),
        .executable(name: "CronHarbor", targets: ["CronHarbor"])
    ],
    targets: [
        .target(
            name: "CronHarborCore",
            path: "Sources/CronHarborCore"
        ),
        .executableTarget(
            name: "CronHarbor",
            dependencies: ["CronHarborCore"],
            path: "Sources/CronHarbor"
        ),
        .testTarget(
            name: "CronHarborCoreTests",
            dependencies: ["CronHarborCore"],
            path: "Tests/CronHarborCoreTests"
        ),
        .testTarget(
            name: "CronHarborAppTests",
            dependencies: ["CronHarbor"],
            path: "Tests/CronHarborAppTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
