// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kilele",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kilele",
            path: "Sources/Kilele",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
