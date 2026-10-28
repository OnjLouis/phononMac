// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhononMac",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SpeechCore", targets: ["SpeechCore"]),
               .library(name: "UpdateCore", targets: ["UpdateCore"])],
    dependencies: [.package(path: "Vendor/PhononTTS")],
    targets: [
        .target(name: "SonicDSP", path: "Vendor/Sonic", publicHeadersPath: "include"),
        .target(name: "SpeechCore", dependencies: ["SonicDSP", .product(name: "ptts", package: "PhononTTS")]),
        .target(name: "UpdateCore"),
        .testTarget(name: "SpeechCoreTests", dependencies: ["SpeechCore"]),
        .testTarget(name: "UpdateCoreTests", dependencies: ["UpdateCore"]),
    ],
    swiftLanguageModes: [.v5]
)
