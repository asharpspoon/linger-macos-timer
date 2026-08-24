// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Linger",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Linger",
            path: "Sources/Linger",
            resources: [
                // 2026-08-23：菜单栏可选图标（用户提供的 4 个 18×18 template PNG）
                .copy("Resources/MenuBarIcons"),
                // 2026-08-24：关于页应用图标（与 app/Dock icns 同源的 PNG）
                .copy("Resources/AboutAssets")
            ],
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
