// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ViFinder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ViFinder",
            path: "Sources/ViFinder",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Quartz"),
                .linkedFramework("QuickLookThumbnailing"),
            ]
        )
    ]
)
