// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WokyMon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WokyMon",
            resources: [
                .copy("Resources/ui")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
