// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoCuration",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PhotoCuration", targets: ["PhotoCuration"])
    ],
    targets: [
        .target(name: "PhotoCuration"),
        .testTarget(name: "PhotoCurationTests", dependencies: ["PhotoCuration"])
    ]
)
