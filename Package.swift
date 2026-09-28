// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipResolved",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipResolved", targets: ["ClipResolved"]),
    ],
    dependencies: [
        .package(path: "external/SD-Offload"),
    ],
    targets: [
        .executableTarget(
            name: "ClipResolved",
            dependencies: [
                .product(name: "OffloadCore", package: "SD-Offload"),
                .product(name: "OffloadEngine", package: "SD-Offload"),
            ],
            path: "Sources/ClipResolved"
        ),
        .testTarget(
            name: "ClipResolvedTests",
            dependencies: ["ClipResolved"],
            path: "Tests/ClipResolvedTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
