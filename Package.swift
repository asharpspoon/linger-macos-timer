// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Linger",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Linger",
            path: "Sources/Linger",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "LingerTests",
            dependencies: ["Linger"],
            path: "Tests/LingerTests"
        )
    ]
)
