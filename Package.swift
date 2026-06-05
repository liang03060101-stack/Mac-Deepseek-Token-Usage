// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekTokenMenu",
    platforms: [
        .macOS(.v13) // 需要 macOS 13+ 以支持 MenuBarExtra
    ],
    products: [
        .executable(
            name: "DeepSeekTokenMenu",
            targets: ["DeepSeekTokenMenu"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekTokenMenu",
            path: "Sources/DeepSeekTokenMenu",
            resources: [
                .process("../../Resources/Assets.xcassets")
            ]
        )
    ]
)
