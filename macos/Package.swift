// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteApp",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "note_coreFFI", path: "Frameworks/note_coreFFI.xcframework"),
        .target(name: "NoteCore", dependencies: ["note_coreFFI"], path: "Sources/NoteCore"),
        .executableTarget(name: "NoteApp", dependencies: ["NoteCore"], path: "Sources/NoteApp"),
    ]
)
