// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AtlasCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "AtlasCore", targets: ["AtlasCore"])
    ],
    targets: [
        .target(name: "AtlasCore"),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"])
    ]
)
