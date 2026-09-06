// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Keyveil",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Keyveil", targets: ["Keyveil"])
    ],
    targets: [
        .executableTarget(
            name: "Keyveil",
            path: "Sources/Keyveil",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KeyveilTests",
            dependencies: ["Keyveil"],
            path: "Tests/KeyveilTests"
        )
    ]
)
