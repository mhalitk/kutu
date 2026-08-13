// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kutu",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KutuCore", targets: ["KutuCore"]),
        .executable(name: "kutu-app", targets: ["kutu-app"])
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .target(name: "KutuCore", dependencies: ["TOMLKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "KutuMac", dependencies: ["KutuCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "kutu-app", dependencies: ["KutuMac"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "kutu-axcheck", dependencies: ["KutuMac"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KutuCoreTests", dependencies: ["KutuCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
