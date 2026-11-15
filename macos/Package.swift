// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zree",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "zree_coreFFI", path: "Frameworks/zree_coreFFI.xcframework"),
        .target(
            name: "ZreeCore",
            dependencies: ["zree_coreFFI"],
            path: "Sources/ZreeCore",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .executableTarget(name: "Zree", dependencies: ["ZreeCore"], path: "Sources/ZreeApp"),
    ]
)
