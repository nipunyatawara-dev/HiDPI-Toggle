// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HiDPIToggle",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .target(
            name: "CGSPrivate",
            path: "Sources/CGSPrivate",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "HiDPIToggle",
            dependencies: ["CGSPrivate"],
            path: "Sources/HiDPIToggle"
        ),
    ]
)
