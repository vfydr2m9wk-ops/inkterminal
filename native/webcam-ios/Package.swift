// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkDOSHubNativeWebcam",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NativeWebcamCapture", targets: ["NativeWebcamCapture"])
    ],
    targets: [
        .target(
            name: "NativeWebcamCapture",
            path: ".",
            sources: ["Native4K60Capture.swift"]
        )
    ]
)