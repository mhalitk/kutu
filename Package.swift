// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kutu",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KutuCore", targets: ["KutuCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .target(name: "KutuCore", dependencies: ["TOMLKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KutuCoreTests", dependencies: ["KutuCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
