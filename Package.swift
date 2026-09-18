//swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-idna",
    products: [
        .library(name: "SwiftIDNA", targets: ["SwiftIDNA"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-dns/swift-highway.git", exact: "1.0.0-alpha.2"),
    ],
    targets: [
        .target(
            name: "SwiftIDNA",
            dependencies: [
                "CSwiftIDNA",
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "Highway", package: "swift-highway"),
            ],
            swiftSettings: settings
        ),
        .target(name: "CSwiftIDNA"),
        .target(
            name: "CSwiftIDNATesting",
            cSettings: cSettingsIgnoringInvalidSourceCharacters
        ),
        .testTarget(
            name: "IDNATests",
            dependencies: [
                "SwiftIDNA",
                "CSwiftIDNATesting",
            ],
            swiftSettings: settings
        ),
    ]
)

var settings: [SwiftSetting] {
    [
        .interoperabilityMode(.Cxx),
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 5.1:macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0"
        ),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 5.3:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"
        ),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 6.2:macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0"
        ),
    ]
}

var cSettingsIgnoringInvalidSourceCharacters: [CSetting] {
    [
        .unsafeFlags(
            [
                "-Wno-unknown-escape-sequence",
                "-Wno-invalid-source-encoding",
            ]
        )
    ]
}
