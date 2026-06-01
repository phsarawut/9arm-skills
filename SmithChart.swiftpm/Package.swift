// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmithChart",
    platforms: [.iOS("17.0")],
    targets: [
        .executableTarget(
            name: "SmithChart",
            path: "Sources"
        )
    ]
)
