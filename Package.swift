// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

#if swift(<6)
let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency")
]
#else
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]
#endif

let package = Package(
    name: "HaishinKit",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .visionOS(.v1),
        .macOS(.v10_15),
        .macCatalyst(.v14)
    ],
    products: [
        .library(name: "HaishinKit", targets: ["HaishinKit"]),
        .library(name: "SRTHaishinKit", targets: ["SRTHaishinKit"]),
        .library(name: "MoQTHaishinKit", targets: ["MoQTHaishinKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/shogo4405/Logboard.git", "2.5.0"..<"2.6.0")
    ],
    targets: [
        .binaryTarget(
            name: "libsrt",
            url: "https://github.com/HaishinKit/libsrt-xcframework/releases/download/v1.5.4/libsrt.xcframework.zip",
            checksum: "76879e2802e45ce043f52871a0a6764d57f833bdb729f2ba6663f4e31d658c4a"
        ),
        .target(
            name: "HaishinKit",
            dependencies: ["Logboard"],
            path: "HaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SRTHaishinKit",
            dependencies: ["libsrt", "HaishinKit"],
            path: "SRTHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MoQTHaishinKit",
            dependencies: ["HaishinKit"],
            path: "MoQTHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HaishinKitTests",
            dependencies: ["HaishinKit"],
            path: "HaishinKit/Tests",
            resources: [
                .process("Asset")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SRTHaishinKitTests",
            dependencies: ["SRTHaishinKit"],
            path: "SRTHaishinKit/Tests",
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v6, .v5]
)
