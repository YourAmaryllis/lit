// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lit",
            path: "Sources/Lit"
        )
    ]
)
