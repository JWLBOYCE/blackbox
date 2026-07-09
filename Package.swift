// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenPilotLogbook",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenPilotLogbook", targets: ["OpenPilotLogbook"]),
        .executable(name: "OpenPilotLogbookCoreUnitTests", targets: ["OpenPilotLogbookCoreUnitTests"]),
        .executable(name: "OpenPilotLogbookCoreSmokeTests", targets: ["OpenPilotLogbookCoreSmokeTests"])
    ],
    targets: [
        .target(
            name: "OpenPilotLogbookCore",
            resources: [
                .copy("Resources/airports.csv"),
                .copy("Resources/earth-blue-marble.jpg")
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "OpenPilotLogbook",
            dependencies: ["OpenPilotLogbookCore"],
            exclude: ["Assets"]
        ),
        .executableTarget(
            name: "OpenPilotLogbookCoreUnitTests",
            dependencies: ["OpenPilotLogbookCore"]
        ),
        .executableTarget(
            name: "OpenPilotLogbookCoreSmokeTests",
            dependencies: ["OpenPilotLogbookCore"]
        )
    ]
)
