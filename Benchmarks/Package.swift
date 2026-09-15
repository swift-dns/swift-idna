// swift-tools-version: 6.3

import CompilerPluginSupport
// MARK: - BEGIN exact copy of the main package's Package.swift
import PackageDescription

let package = Package(
    name: "swift-idna",
    products: [
        .library(name: "SwiftIDNA", targets: ["SwiftIDNA"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "SwiftIDNA",
            dependencies: [
                "CSwiftIDNA",
                .product(name: "BasicContainers", package: "swift-collections"),
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
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 6.2:macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0"
        ),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 5.3:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"
        ),
        .enableExperimentalFeature(
            "AvailabilityMacro=SwiftStdlib 5.1:macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0"
        ),
        .treatWarning("StrictMemorySafety", as: .warning),
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
// MARK: - END exact copy of the main package's Package.swift

// MARK: - Add benchmark stuff now

package.platforms = [.macOS(.v26)]

package.dependencies.append(
    .package(
        url: "https://github.com/MahdiBM/package-benchmark.git",
        branch: "mmbm-range-relative-thresholds-options-bak"
    ),
)

package.dependencies.append(
    .package(
        url: "https://github.com/apple/swift-foundation-icu.git",
        branch: "main"
    )
)

package.targets += [
    .target(
        name: "FoundationIDNA",
        dependencies: [
            .product(name: "_FoundationICU", package: "swift-foundation-icu")
        ],
        path: "FoundationIDNA",
        swiftSettings: settings
    ),
    .executableTarget(
        name: "ToASCIIBenchs",
        dependencies: [
            .product(name: "Benchmark", package: "package-benchmark"),
            "SwiftIDNA",
            "FoundationIDNA",
        ],
        path: "ToASCII",
        swiftSettings: settings,
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
        ]
    ),
    .executableTarget(
        name: "ToUnicodeBenchs",
        dependencies: [
            .product(name: "Benchmark", package: "package-benchmark"),
            "SwiftIDNA",
            "FoundationIDNA",
        ],
        path: "ToUnicode",
        swiftSettings: settings,
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
        ]
    ),
]
