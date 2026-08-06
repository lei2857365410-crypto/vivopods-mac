// swift-tools-version:6.0
import PackageDescription

// 注意：本机只装了 Command Line Tools（无完整 Xcode），工具链里既没有 XCTest
// 也没有 swift-testing 模块，因此 `swift test` 不可用。测试改为零依赖的自测
// 可执行文件：`swift run vivopods-selftest`。
let package = Package(
    name: "VivoPods",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VivoPodsKit", targets: ["VivoPodsKit"]),
        // 协议探测 CLI：先用它对真机验证协议，再谈 GUI
        .executable(name: "vivoprobe", targets: ["VivoProbe"]),
        // 协议自测（替代 swift test）
        .executable(name: "vivopods-selftest", targets: ["VivoSelfTest"]),
        // 状态栏 App
        .executable(name: "VivoPods", targets: ["VivoPodsApp"]),
    ],
    targets: [
        .target(
            name: "VivoPodsKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VivoProbe",
            dependencies: ["VivoPodsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VivoSelfTest",
            dependencies: ["VivoPodsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VivoPodsApp",
            dependencies: ["VivoPodsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
