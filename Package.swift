// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Keyveil",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Keyveil", targets: ["Keyveil"])
    ],
    targets: [
        .executableTarget(
            name: "Keyveil",
            path: "Sources/Keyveil"
        )
    ]
)
