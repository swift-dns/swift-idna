import Benchmark
import FoundationIDNA
import SwiftIDNA

let benchmarks: @Sendable () -> Void = {
    unsafe Benchmark.defaultConfiguration.maxDuration = .seconds(6)

    let strictConfig = IDNA(configuration: .mostStrict)
    let laxConfig = IDNA(configuration: .mostLax)
    let nameAndConfigs = [
        ("Strict", strictConfig),
        ("Lax", laxConfig),
    ]

    /// Swift uses `_SmallString` internally for strings <= 15 utf8s.
    /// We have a benchmark for both `_SmallString` and heap-allocated `String` cases.

    /// Mark: - Lowercased_google.com

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_CPU_8M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<8_000_000 {
            var domainName = "google.com"
            domainName = try! strictConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "google.com"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_Instructions",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "google.com"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_CPU_1M_ICU",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<1_000_000 {
            var domainName = "google.com"
            domainName = UIDNAHookICU.decode(domainName)!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_Malloc_ICU",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "google.com"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_google_dot_com_Instructions_ICU",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "google.com"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    /// Mark: - Uppercased_google.com

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_CPU_5M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<5_000_000 {
            var domainName = "GOOGLE.COM"
            domainName = try! strictConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "GOOGLE.COM"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_Instructions",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "GOOGLE.COM"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_CPU_1M_ICU",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<1_000_000 {
            var domainName = "GOOGLE.COM"
            domainName = UIDNAHookICU.decode(domainName)!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_Malloc_ICU",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "GOOGLE.COM"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_Instructions_ICU",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "GOOGLE.COM"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    /// Mark: - Lowercased_app-analytics-services.com

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_CPU_6M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<6_000_000 {
            var domainName = "app-analytics-services.com"
            domainName = try! strictConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "app-analytics-services.com"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_Instructions",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "app-analytics-services.com"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_CPU_1M_ICU",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<1_000_000 {
            var domainName = "app-analytics-services.com"
            domainName = UIDNAHookICU.decode(domainName)!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_Malloc_ICU",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "app-analytics-services.com"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_Instructions_ICU",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "app-analytics-services.com"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    /// Mark: - Uppercased_app-analytics-services.com

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_CPU_3M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<3_000_000 {
            var domainName = "APP-ANALYTICS-SERVICES.COM"
            domainName = try! strictConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "APP-ANALYTICS-SERVICES.COM"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_Instructions",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "APP-ANALYTICS-SERVICES.COM"
        domainName = try! strictConfig.toUnicode(domainName: domainName)
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_CPU_1M_ICU",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<1_000_000 {
            var domainName = "APP-ANALYTICS-SERVICES.COM"
            domainName = UIDNAHookICU.decode(domainName)!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_Malloc_ICU",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "APP-ANALYTICS-SERVICES.COM"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_Instructions_ICU",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "APP-ANALYTICS-SERVICES.COM"
        domainName = UIDNAHookICU.decode(domainName)!
        blackHole(domainName)
    }

    /// Mark: - Multiple_ASCII_Domains data
    /// Grabbed from the most popular domains. All ASCII; 4 of them uppercased.

    // [
    //     "google.com",
    //     "googleapis.com",
    //     "cloudflare.com",
    //     "gstatic.com",
    //     "apple.com",
    //     "MICROSOFT.COM",
    //     "facebook.com",
    //     "AMAZONAWS.COM",
    //     "googlevideo.com",
    //     "fbcdn.net",
    //     "gvt1.com",
    //     "fastly.net",
    //     "samsung.com",
    //     "sentry.io",
    //     "dns.google",
    //     "prodregistryv2.org",
    //     "msn.com",
    //     "ROBLOX.COM",
    //     "app-analytics-services.com",
    //     "APP-MEASUREMENT.COM",
    // ]
    let asciiDomains: [20 of [UInt8]] = [
        [
            0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x2E, 0x63,
            0x6F, 0x6D,
        ],
        [
            0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x61, 0x70,
            0x69, 0x73, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x63, 0x6C, 0x6F, 0x75, 0x64, 0x66, 0x6C, 0x61,
            0x72, 0x65, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x67, 0x73, 0x74, 0x61, 0x74, 0x69, 0x63, 0x2E,
            0x63, 0x6F, 0x6D,
        ],
        [
            0x61, 0x70, 0x70, 0x6C, 0x65, 0x2E, 0x63, 0x6F,
            0x6D,
        ],
        [
            0x4D, 0x49, 0x43, 0x52, 0x4F, 0x53, 0x4F, 0x46,
            0x54, 0x2E, 0x43, 0x4F, 0x4D,
        ],
        [
            0x66, 0x61, 0x63, 0x65, 0x62, 0x6F, 0x6F, 0x6B,
            0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x41, 0x4D, 0x41, 0x5A, 0x4F, 0x4E, 0x41, 0x57,
            0x53, 0x2E, 0x43, 0x4F, 0x4D,
        ],
        [
            0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, 0x76, 0x69,
            0x64, 0x65, 0x6F, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x66, 0x62, 0x63, 0x64, 0x6E, 0x2E, 0x6E, 0x65,
            0x74,
        ],
        [
            0x67, 0x76, 0x74, 0x31, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x66, 0x61, 0x73, 0x74, 0x6C, 0x79, 0x2E, 0x6E,
            0x65, 0x74,
        ],
        [
            0x73, 0x61, 0x6D, 0x73, 0x75, 0x6E, 0x67, 0x2E,
            0x63, 0x6F, 0x6D,
        ],
        [
            0x73, 0x65, 0x6E, 0x74, 0x72, 0x79, 0x2E, 0x69,
            0x6F,
        ],
        [
            0x64, 0x6E, 0x73, 0x2E, 0x67, 0x6F, 0x6F, 0x67,
            0x6C, 0x65,
        ],
        [
            0x70, 0x72, 0x6F, 0x64, 0x72, 0x65, 0x67, 0x69,
            0x73, 0x74, 0x72, 0x79, 0x76, 0x32, 0x2E, 0x6F,
            0x72, 0x67,
        ],
        [
            0x6D, 0x73, 0x6E, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x52, 0x4F, 0x42, 0x4C, 0x4F, 0x58, 0x2E, 0x43,
            0x4F, 0x4D,
        ],
        [
            0x61, 0x70, 0x70, 0x2D, 0x61, 0x6E, 0x61, 0x6C,
            0x79, 0x74, 0x69, 0x63, 0x73, 0x2D, 0x73, 0x65,
            0x72, 0x76, 0x69, 0x63, 0x65, 0x73, 0x2E, 0x63,
            0x6F, 0x6D,
        ],
        [
            0x41, 0x50, 0x50, 0x2D, 0x4D, 0x45, 0x41, 0x53,
            0x55, 0x52, 0x45, 0x4D, 0x45, 0x4E, 0x54, 0x2E,
            0x43, 0x4F, 0x4D,
        ],
    ]

    let asciiDomainsICU: [20 of String] = [
        "google.com",
        "googleapis.com",
        "cloudflare.com",
        "gstatic.com",
        "apple.com",
        "MICROSOFT.COM",
        "facebook.com",
        "AMAZONAWS.COM",
        "googlevideo.com",
        "fbcdn.net",
        "gvt1.com",
        "fastly.net",
        "samsung.com",
        "sentry.io",
        "dns.google",
        "prodregistryv2.org",
        "msn.com",
        "ROBLOX.COM",
        "app-analytics-services.com",
        "APP-MEASUREMENT.COM",
    ]

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_CPU_4M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        var rng = FastRNG()
        for _ in 0..<4_000_000 {
            let idx = Int(rng.next() % UInt64(asciiDomains.count))
            let result = try! strictConfig.toUnicode(
                span: asciiDomains[idx].span
            )
            let domainName = unsafe result.collect().unsafelyUnwrapped
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        for idx in asciiDomains.indices {
            let result = try! strictConfig.toUnicode(
                span: asciiDomains[idx].span
            )
            let domainName = unsafe result.collect().unsafelyUnwrapped
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_Instructions",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        for idx in asciiDomains.indices {
            let result = try! strictConfig.toUnicode(
                span: asciiDomains[idx].span
            )
            let domainName = unsafe result.collect().unsafelyUnwrapped
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_CPU_1M_ICU",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        var rng = FastRNG()
        for _ in 0..<1_000_000 {
            let idx = Int(rng.next() % UInt64(asciiDomainsICU.count))
            let domainName = UIDNAHookICU.decode(asciiDomainsICU[idx])!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_Malloc_ICU",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        for idx in asciiDomainsICU.indices {
            let domainName = UIDNAHookICU.decode(asciiDomainsICU[idx])!
            blackHole(domainName)
        }
    }

    Benchmark(
        "To_Unicode_Multiple_ASCII_Domains_Instructions_ICU",
        configuration: .init(
            metrics: [.instructions],
            warmupIterations: 100,
            maxIterations: 10,
        )
    ) { benchmark in
        for idx in asciiDomainsICU.indices {
            let domainName = UIDNAHookICU.decode(asciiDomainsICU[idx])!
            blackHole(domainName)
        }
    }

    /// Mark: - Multiple_Domains data
    /// Grabbed from Cloudflare top domains

    // [
    //     "xn----8sbkrdkflhbom0gg8c.xn--p1ai",
    //     "xn--80akicokc0aablc.xn--p1ai",
    //     "xn--b1aew.xn--p1ai",
    //     "xn--ghq880n3na965a.com",
    //     "xn--ghqu5fm27b67w.com",
    //     "xn--gps-8y0gm25n.xn--55qx5d",
    //     "xn--ijanec-9jb.eu",
    //     "xn--lep-tma39c.tv",
    //     "xn--mgbkt9eckr.net",
    //     "xn--ngstr-lra8j.com",
    //     "xn--pckua2a7gp15o89zb.com",
    //     "xn--r1a.website",
    //     "xn--szukamksiki-4kb16m.pl",
    // ]
    let multipleDomains: [13 of [UInt8]] = [
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x2D, 0x2D, 0x38, 0x73,
            0x62, 0x6B, 0x72, 0x64, 0x6B, 0x66, 0x6C, 0x68,
            0x62, 0x6F, 0x6D, 0x30, 0x67, 0x67, 0x38, 0x63,
            0x2E, 0x78, 0x6E, 0x2D, 0x2D, 0x70, 0x31, 0x61,
            0x69,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x38, 0x30, 0x61, 0x6B,
            0x69, 0x63, 0x6F, 0x6B, 0x63, 0x30, 0x61, 0x61,
            0x62, 0x6C, 0x63, 0x2E, 0x78, 0x6E, 0x2D, 0x2D,
            0x70, 0x31, 0x61, 0x69,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x62, 0x31, 0x61, 0x65,
            0x77, 0x2E, 0x78, 0x6E, 0x2D, 0x2D, 0x70, 0x31,
            0x61, 0x69,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x67, 0x68, 0x71, 0x38,
            0x38, 0x30, 0x6E, 0x33, 0x6E, 0x61, 0x39, 0x36,
            0x35, 0x61, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x67, 0x68, 0x71, 0x75,
            0x35, 0x66, 0x6D, 0x32, 0x37, 0x62, 0x36, 0x37,
            0x77, 0x2E, 0x63, 0x6F, 0x6D,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x67, 0x70, 0x73, 0x2D,
            0x38, 0x79, 0x30, 0x67, 0x6D, 0x32, 0x35, 0x6E,
            0x2E, 0x78, 0x6E, 0x2D, 0x2D, 0x35, 0x35, 0x71,
            0x78, 0x35, 0x64,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x69, 0x6A, 0x61, 0x6E,
            0x65, 0x63, 0x2D, 0x39, 0x6A, 0x62, 0x2E, 0x65,
            0x75,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x6C, 0x65, 0x70, 0x2D,
            0x74, 0x6D, 0x61, 0x33, 0x39, 0x63, 0x2E, 0x74,
            0x76,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x6D, 0x67, 0x62, 0x6B,
            0x74, 0x39, 0x65, 0x63, 0x6B, 0x72, 0x2E, 0x6E,
            0x65, 0x74,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x6E, 0x67, 0x73, 0x74,
            0x72, 0x2D, 0x6C, 0x72, 0x61, 0x38, 0x6A, 0x2E,
            0x63, 0x6F, 0x6D,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x70, 0x63, 0x6B, 0x75,
            0x61, 0x32, 0x61, 0x37, 0x67, 0x70, 0x31, 0x35,
            0x6F, 0x38, 0x39, 0x7A, 0x62, 0x2E, 0x63, 0x6F,
            0x6D,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x72, 0x31, 0x61, 0x2E,
            0x77, 0x65, 0x62, 0x73, 0x69, 0x74, 0x65,
        ],
        [
            0x78, 0x6E, 0x2D, 0x2D, 0x73, 0x7A, 0x75, 0x6B,
            0x61, 0x6D, 0x6B, 0x73, 0x69, 0x6B, 0x69, 0x2D,
            0x34, 0x6B, 0x62, 0x31, 0x36, 0x6D, 0x2E, 0x70,
            0x6C,
        ],
    ]

    let multipleDomainsICU: [13 of String] = [
        "xn----8sbkrdkflhbom0gg8c.xn--p1ai",
        "xn--80akicokc0aablc.xn--p1ai",
        "xn--b1aew.xn--p1ai",
        "xn--ghq880n3na965a.com",
        "xn--ghqu5fm27b67w.com",
        "xn--gps-8y0gm25n.xn--55qx5d",
        "xn--ijanec-9jb.eu",
        "xn--lep-tma39c.tv",
        "xn--mgbkt9eckr.net",
        "xn--ngstr-lra8j.com",
        "xn--pckua2a7gp15o89zb.com",
        "xn--r1a.website",
        "xn--szukamksiki-4kb16m.pl",
    ]

    for (namePrefix, idnaConfig) in nameAndConfigs {
        /// Mark: - 生命之花.中国
        /// Grabbed from Cloudflare top 100K domains

        Benchmark(
            "To_Unicode_\(namePrefix)_生命之花_dot_中国_CPU_200K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 15,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<200_000 {
                var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
                domainName = try! idnaConfig.toUnicode(domainName: domainName)
                blackHole(domainName)
            }
        }

        Benchmark(
            "To_Unicode_\(namePrefix)_生命之花_dot_中国_Malloc",
            configuration: .init(
                metrics: [.mallocCountTotal],
                warmupIterations: 1,
                maxIterations: 10,
            )
        ) { benchmark in
            var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
            domainName = try! idnaConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }

        Benchmark(
            "To_Unicode_\(namePrefix)_生命之花_dot_中国_Instructions",
            configuration: .init(
                metrics: [.instructions],
                warmupIterations: 100,
                maxIterations: 10,
            )
        ) { benchmark in
            var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
            domainName = try! idnaConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }

        if namePrefix.lowercased() == "lax" {
            Benchmark(
                "To_Unicode_\(namePrefix)_生命之花_dot_中国_CPU_200K_ICU",
                configuration: .init(
                    metrics: [.cpuUser],
                    warmupIterations: 15,
                    maxIterations: 1000,
                )
            ) { benchmark in
                for _ in 0..<200_000 {
                    var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
                    domainName = UIDNAHookICU.decode(domainName)!
                    blackHole(domainName)
                }
            }

            Benchmark(
                "To_Unicode_\(namePrefix)_生命之花_dot_中国_Malloc_ICU",
                configuration: .init(
                    metrics: [.mallocCountTotal],
                    warmupIterations: 1,
                    maxIterations: 10,
                )
            ) { benchmark in
                var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
                domainName = UIDNAHookICU.decode(domainName)!
                blackHole(domainName)
            }

            Benchmark(
                "To_Unicode_\(namePrefix)_生命之花_dot_中国_Instructions_ICU",
                configuration: .init(
                    metrics: [.instructions],
                    warmupIterations: 100,
                    maxIterations: 10,
                )
            ) { benchmark in
                var domainName = "xn--9iqv4mb85adml.xn--fiqs8s"
                domainName = UIDNAHookICU.decode(domainName)!
                blackHole(domainName)
            }
        }

        /// Mark: - Multiple_Domains

        let multipleDomainsCount = namePrefix.lowercased() == "lax" ? 300_000 : 200_000
        let multipleDomainsCountLabel = namePrefix.lowercased() == "lax" ? "300K" : "200K"

        Benchmark(
            "To_Unicode_\(namePrefix)_Multiple_Domains_CPU_\(multipleDomainsCountLabel)",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 15,
                maxIterations: 1000,
            )
        ) { benchmark in
            var rng = FastRNG()
            for _ in 0..<multipleDomainsCount {
                let idx = Int(rng.next() % UInt64(multipleDomains.count))
                let result = try! idnaConfig.toUnicode(
                    span: multipleDomains[idx].span
                )
                let domainName = unsafe result.collect().unsafelyUnwrapped
                blackHole(domainName)
            }
        }

        Benchmark(
            "To_Unicode_\(namePrefix)_Multiple_Domains_Malloc",
            configuration: .init(
                metrics: [.mallocCountTotal],
                warmupIterations: 1,
                maxIterations: 10,
            )
        ) { benchmark in
            for idx in multipleDomains.indices {
                let result = try! idnaConfig.toUnicode(
                    span: multipleDomains[idx].span
                )
                let domainName = unsafe result.collect().unsafelyUnwrapped
                blackHole(domainName)
            }
        }

        Benchmark(
            "To_Unicode_\(namePrefix)_Multiple_Domains_Instructions",
            configuration: .init(
                metrics: [.instructions],
                warmupIterations: 100,
                maxIterations: 10,
            )
        ) { benchmark in
            for idx in multipleDomains.indices {
                let result = try! idnaConfig.toUnicode(
                    span: multipleDomains[idx].span
                )
                let domainName = unsafe result.collect().unsafelyUnwrapped
                blackHole(domainName)
            }
        }

        if namePrefix.lowercased() == "lax" {
            Benchmark(
                "To_Unicode_\(namePrefix)_Multiple_Domains_CPU_\(multipleDomainsCountLabel)_ICU",
                configuration: .init(
                    metrics: [.cpuUser],
                    warmupIterations: 15,
                    maxIterations: 1000,
                )
            ) { benchmark in
                var rng = FastRNG()
                for _ in 0..<multipleDomainsCount {
                    let idx = Int(rng.next() % UInt64(multipleDomainsICU.count))
                    let domainName = UIDNAHookICU.decode(multipleDomainsICU[idx])!
                    blackHole(domainName)
                }
            }

            Benchmark(
                "To_Unicode_\(namePrefix)_Multiple_Domains_Malloc_ICU",
                configuration: .init(
                    metrics: [.mallocCountTotal],
                    warmupIterations: 1,
                    maxIterations: 10,
                )
            ) { benchmark in
                for idx in multipleDomainsICU.indices {
                    let domainName = UIDNAHookICU.decode(multipleDomainsICU[idx])!
                    blackHole(domainName)
                }
            }

            Benchmark(
                "To_Unicode_\(namePrefix)_Multiple_Domains_Instructions_ICU",
                configuration: .init(
                    metrics: [.instructions],
                    warmupIterations: 100,
                    maxIterations: 10,
                )
            ) { benchmark in
                for idx in multipleDomainsICU.indices {
                    let domainName = UIDNAHookICU.decode(multipleDomainsICU[idx])!
                    blackHole(domainName)
                }
            }
        }
    }
}
