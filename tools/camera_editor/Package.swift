// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CameraEditor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CameraEditor",
            path: "Sources/CameraEditor",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
