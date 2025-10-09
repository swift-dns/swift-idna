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
        "To_Unicode_Lowercased_google_dot_com_CPU_8M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
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

    /// Mark: - Uppercased_google.com

    Benchmark(
        "To_Unicode_Uppercased_google_dot_com_CPU_8M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<8_000_000 {
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

    /// Mark: - Lowercased_app-analytics-services.com

    Benchmark(
        "To_Unicode_Lowercased_app-analytics-services_dot_com_CPU_4M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<4_000_000 {
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

    /// Mark: - Uppercased_app-analytics-services.com

    Benchmark(
        "To_Unicode_Uppercased_app-analytics-services_dot_com_CPU_4M",
        configuration: .init(
            metrics: [.cpuUser],
            warmupIterations: 5,
            maxIterations: 1000,
        )
    ) { benchmark in
        for _ in 0..<4_000_000 {
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

    for (namePrefix, idnaConfig) in nameAndConfigs {
        /// Mark: - öob.se
        /// Grabbed from Cloudflare top 1M domains

        Benchmark(
            "To_Unicode_\(namePrefix)_öob_dot_se_CPU_200K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 5,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<200_000 {
                var domainName = "xn--ob-eka.se"
                domainName = try! idnaConfig.toUnicode(domainName: domainName)
                blackHole(domainName)
            }
        }

        Benchmark(
            "To_Unicode_\(namePrefix)_öob_dot_se_Malloc",
            configuration: .init(
                metrics: [.mallocCountTotal],
                warmupIterations: 1,
                maxIterations: 10,
            )
        ) { benchmark in
            var domainName = "xn--ob-eka.se"
            domainName = try! idnaConfig.toUnicode(domainName: domainName)
            blackHole(domainName)
        }

        /// Mark: - 生命之花.中国
        /// Grabbed from Cloudflare top 100K domains

        Benchmark(
            "To_Unicode_\(namePrefix)_生命之花_dot_中国_CPU_100K",
            configuration: .init(
                metrics: [.cpuUser],
                warmupIterations: 5,
                maxIterations: 1000,
            )
        ) { benchmark in
            for _ in 0..<100_000 {
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
    }
}
