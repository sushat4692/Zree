// swift-tools-version: 6.0
import Foundation
import PackageDescription

// git2's `https` feature pulls openssl-sys even on macOS (libgit2 itself uses
// SecureTransport there), so the final link still needs OpenSSL. Prefer a
// Homebrew install and allow an override for other setups.
let opensslLibOverride = ProcessInfo.processInfo.environment["ZREE_OPENSSL_LIB"]
let opensslCandidates = [
    opensslLibOverride,
    "/opt/homebrew/opt/openssl@3/lib",
    "/opt/homebrew/opt/openssl@4/lib",
    "/usr/local/opt/openssl@3/lib",
    "/usr/local/opt/openssl@4/lib",
].compactMap { $0 }

let opensslLib = opensslCandidates.first {
    FileManager.default.fileExists(atPath: $0 + "/libssl.dylib")
        || FileManager.default.fileExists(atPath: $0 + "/libssl.a")
}

var coreLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("z"),
    .linkedLibrary("iconv"),
    .linkedFramework("Security"),
    .linkedFramework("CoreFoundation"),
    .linkedFramework("SystemConfiguration"),
]

if let opensslLib {
    coreLinkerSettings.append(.unsafeFlags(["-L\(opensslLib)"]))
    coreLinkerSettings.append(.linkedLibrary("ssl"))
    coreLinkerSettings.append(.linkedLibrary("crypto"))
}

let package = Package(
    name: "Zree",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "zree_coreFFI", path: "Frameworks/zree_coreFFI.xcframework"),
        .target(
            name: "ZreeEditor",
            dependencies: ["ZreeCore"],
            path: "Sources/ZreeEditor",
            linkerSettings: coreLinkerSettings
        ),
        .target(
            name: "ZreeCore",
            dependencies: ["zree_coreFFI"],
            path: "Sources/ZreeCore",
            linkerSettings: coreLinkerSettings
        ),
        .executableTarget(
            name: "Zree",
            dependencies: ["ZreeCore", "ZreeEditor"],
            path: "Sources/ZreeApp"
        ),
        .testTarget(
            name: "ZreeEditorTests",
            dependencies: ["ZreeEditor", "ZreeCore"],
            path: "Tests/ZreeEditorTests"
        ),
    ]
)
