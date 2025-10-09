import Benchmark
import SwiftIDNA

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.maxDuration = .seconds(5)

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
        "To_ASCII_Lowercased_google_dot_com_CPU_8M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<8_000_000 {
            var domainName = "google.com"
            let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }
    }

    Benchmark(
        "To_ASCII_Lowercased_google_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "google.com"
        let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
        blackHole(converted)
    }

    /// Mark: - Uppercased_google.com

    Benchmark(
        "To_ASCII_Uppercased_google_dot_com_CPU_10M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<10_000_000 {
            var domainName = "GOOGLE.COM"
            let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }
    }

    Benchmark(
        "To_ASCII_Uppercased_google_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "GOOGLE.COM"
        let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
        blackHole(converted)
    }

    /// Mark: - Lowercased_app-analytics-services.com

    Benchmark(
        "To_ASCII_Lowercased_app-analytics-services_dot_com_CPU_5M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<5_000_000 {
            var domainName = "app-analytics-services.com"
            let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }
    }

    Benchmark(
        "To_ASCII_Lowercased_app-analytics-services_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "app-analytics-services.com"
        let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
        blackHole(converted)
    }

    /// Mark: - Uppercased_app-analytics-services.com

    Benchmark(
        "To_ASCII_Uppercased_app-analytics-services_dot_com_CPU_5M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<5_000_000 {
            var domainName = "APP-ANALYTICS-SERVICES.COM"
            let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }
    }

    Benchmark(
        "To_ASCII_Uppercased_app-analytics-services_dot_com_Malloc",
        configuration: .init(
            metrics: [.mallocCountTotal],
            warmupIterations: 1,
            maxIterations: 10,
        )
    ) { benchmark in
        var domainName = "APP-ANALYTICS-SERVICES.COM"
        let converted: Void = try! strictConfig.toASCII(domainName: &domainName)
        blackHole(converted)
    }

    for (namePrefix, idnaConfig) in nameAndConfigs {
        /// Mark: - öob.se
        /// Grabbed from Cloudflare top 1M domains

        Benchmark(
            "To_ASCII_\(namePrefix)_öob_dot_se_CPU_200K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 5,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<200_000 {
                var domainName = "öob.dot"
                let converted: Void = try! idnaConfig.toASCII(domainName: &domainName)
                blackHole(converted)
            }
        }

        Benchmark(
            "To_ASCII_\(namePrefix)_öob_dot_se_Malloc",
            configuration: .init(
                metrics: [.mallocCountTotal],
                warmupIterations: 1,
                maxIterations: 10,
            )
        ) { benchmark in
            var domainName = "öob.dot"
            let converted: Void = try! idnaConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }

        /// Mark: - 生命之花.中国
        /// Grabbed from Cloudflare top 100K domains

        Benchmark(
            "To_ASCII_\(namePrefix)_生命之花_dot_中国_CPU_200K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 5,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<200_000 {
                var domainName = "生命之花.中国"
                let converted: Void = try! idnaConfig.toASCII(domainName: &domainName)
                blackHole(converted)
            }
        }

        Benchmark(
            "To_ASCII_\(namePrefix)_生命之花_dot_中国_Malloc",
            configuration: .init(
                metrics: [.mallocCountTotal],
                warmupIterations: 1,
                maxIterations: 10,
            )
        ) { benchmark in
            var domainName = "生命之花.中国"
            let converted: Void = try! idnaConfig.toASCII(domainName: &domainName)
            blackHole(converted)
        }
    }
}
