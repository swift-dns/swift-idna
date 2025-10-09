// swift-tools-version: 6.2

import CompilerPluginSupport
// MARK: - BEGIN exact copy of the main package's Package.swift
import PackageDescription

let package = Package(
    name: "swift-idna",
    products: [
        .library(name: "SwiftIDNA", targets: ["SwiftIDNA"])
    ],
    targets: [
        .target(
            name: "SwiftIDNA",
            dependencies: [
                "CSwiftIDNA"
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
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("StrictMemorySafety"),
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

package.targets += [
    .executableTarget(
        name: "ToASCIIBenchs",
        dependencies: [
            .product(name: "Benchmark", package: "package-benchmark"),
            "SwiftIDNA",
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
            "SwiftIDNA",
            .product(name: "Benchmark", package: "package-benchmark"),
        ],
        path: "ToUnicode",
        swiftSettings: settings,
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
        ]
    ),
]
