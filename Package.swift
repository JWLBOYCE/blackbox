// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenPilotLogbook",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenPilotLogbook", targets: ["OpenPilotLogbook"]),
        .executable(name: "OpenPilotLogbookCoreSmokeTests", targets: ["OpenPilotLogbookCoreSmokeTests"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "OpenPilotLogbookCore",
            dependencies: ["CSQLite"],
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
            name: "OpenPilotLogbookCoreSmokeTests",
            dependencies: ["OpenPilotLogbookCore"]
        )
    ]
)
