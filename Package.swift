// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanDisk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CleanDisk", targets: ["CleanDisk"])
    ],
    targets: [
        .executableTarget(
            name: "CleanDisk",
            path: "Sources"
        )
    ]
)
