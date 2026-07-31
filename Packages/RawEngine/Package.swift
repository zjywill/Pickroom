// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RawEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RawEngine", targets: ["RawEngine"])
    ],
    targets: [
        .binaryTarget(
            name: "LibRaw",
            path: "Libraries/LibRaw.xcframework"
        ),
        .target(
            name: "CRawEngine",
            dependencies: ["LibRaw"],
            path: "Sources/CRawEngine",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath(
                    "../../Libraries/LibRaw.xcframework/macos-arm64_x86_64/LibRaw.framework/Headers"
                )
            ]
        ),
        .target(
            name: "RawEngine",
            dependencies: ["CRawEngine"],
            path: "Sources/RawEngine"
        )
    ]
)
