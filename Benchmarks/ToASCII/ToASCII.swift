import Benchmark
import SwiftIDNA

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.maxDuration = .seconds(6)

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
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<8_000_000 {
            var domainName = "google.com"
            domainName = try! strictConfig.toASCII(domainName: domainName)
            blackHole(domainName)
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
        domainName = try! strictConfig.toASCII(domainName: domainName)
        blackHole(domainName)
    }

    /// Mark: - Uppercased_google.com

    Benchmark(
        "To_ASCII_Uppercased_google_dot_com_CPU_10M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<10_000_000 {
            var domainName = "GOOGLE.COM"
            domainName = try! strictConfig.toASCII(domainName: domainName)
            blackHole(domainName)
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
        domainName = try! strictConfig.toASCII(domainName: domainName)
        blackHole(domainName)
    }

    /// Mark: - Lowercased_app-analytics-services.com

    Benchmark(
        "To_ASCII_Lowercased_app-analytics-services_dot_com_CPU_5M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<5_000_000 {
            var domainName = "app-analytics-services.com"
            domainName = try! strictConfig.toASCII(domainName: domainName)
            blackHole(domainName)
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
        domainName = try! strictConfig.toASCII(domainName: domainName)
        blackHole(domainName)
    }

    /// Mark: - Uppercased_app-analytics-services.com

    Benchmark(
        "To_ASCII_Uppercased_app-analytics-services_dot_com_CPU_5M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 15,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<5_000_000 {
            var domainName = "APP-ANALYTICS-SERVICES.COM"
            domainName = try! strictConfig.toASCII(domainName: domainName)
            blackHole(domainName)
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
        domainName = try! strictConfig.toASCII(domainName: domainName)
        blackHole(domainName)
    }

    for (namePrefix, idnaConfig) in nameAndConfigs {
        /// Mark: - öob.se
        /// Grabbed from Cloudflare top 1M domains

        Benchmark(
            "To_ASCII_\(namePrefix)_öob_dot_se_CPU_300K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 15,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<300_000 {
                var domainName = "öob.dot"
                domainName = try! idnaConfig.toASCII(domainName: domainName)
                blackHole(domainName)
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
            domainName = try! idnaConfig.toASCII(domainName: domainName)
            blackHole(domainName)
        }

        /// Mark: - 生命之花.中国
        /// Grabbed from Cloudflare top 100K domains

        Benchmark(
            "To_ASCII_\(namePrefix)_生命之花_dot_中国_CPU_200K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 15,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<200_000 {
                var domainName = "生命之花.中国"
                domainName = try! idnaConfig.toASCII(domainName: domainName)
                blackHole(domainName)
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
            domainName = try! idnaConfig.toASCII(domainName: domainName)
            blackHole(domainName)
        }
    }
}
