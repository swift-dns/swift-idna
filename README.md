<p>
    <a href="https://github.com/swift-dns/swift-idna/actions/workflows/unit-tests.yml">
        <img
            src="https://img.shields.io/github/actions/workflow/status/swift-dns/swift-idna/unit-tests.yml?event=push&style=plastic&logo=github&label=unit-tests&logoColor=%23ccc"
            alt="Unit Tests CI"
        >
    </a>
    <a href="https://github.com/swift-dns/swift-idna/actions/workflows/benchmarks.yml">
        <img
            src="https://img.shields.io/github/actions/workflow/status/swift-dns/swift-idna/benchmarks.yml?event=push&style=plastic&logo=github&label=benchmarks&logoColor=%23ccc"
            alt="Benchmarks CI"
        >
    </a>
    <a href="https://codecov.io/gh/swift-dns/swift-idna">
        <img
            src="https://codecov.io/gh/swift-dns/swift-idna/graph/badge.svg?token=KW7Y46RYYD"
            alt="Codecov Tests Code Coverage"
        >
    </a>
    <a href="https://swift.org">
        <img
            src="https://design.vapor.codes/images/swift63up.svg"
            alt="Swift 6.3+"
        >
    </a>
</p>

# swift-idna

A high performance, highly optimized multi-platform implementation of Punycode and IDNA (Internationalized Domain Names in Applications) as per [RFC 5891](https://datatracker.ietf.org/doc/html/rfc5891) and friends.

## Table of Contents

- [Notes](#notes)
- [Usage](#usage)
- [Implementation](#implementation)
  - [Current supported IDNA flags](#current-supported-idna-flags)
- [Benchmark Comparisons VS swift-foundation's ICU](#benchmark-comparisons-vs-swift-foundations-icu)
  - [Summary](#summary)
  - [Non-ASCII Domain Names](#non-ascii-domain-names)
    - [CPU Time](#cpu-time)
    - [Malloc Count](#malloc-count)
  - [ASCII Domain Names](#ascii-domain-names)
    - [CPU Time](#cpu-time-1)
    - [Malloc Count](#malloc-count-1)
- [How To Add swift-idna To Your Project](#how-to-add-swift-idna-to-your-project)
- [Acknowledgments](#acknowledgments)

## Notes

- The only dependency of `swift-idna` is `swift-collections`, and it does not depend on `Foundation`.
- Unit tests extensively run against 6400+ Unicode 17 test cases.
- The C code is all auto-generated from some Unicode files.

## Usage

Initialize `IDNA` with your preferred configuration, then use `toASCII(domainName:)` and `toUnicode(domainName:)`:

```swift
import SwiftIDNA

let idna = IDNA(configuration: .mostStrict)

/// Turn user input into a IDNA-compatible domain name using toASCII:
print(idna.toASCII(domainName: "新华网.中国"))
/// prints "xn--xkrr14bows.xn--fiqs8s"

/// Turn back an IDNA-compatible domain name to its Unicode representation using toUnicode:
print(idna.toUnicode(domainName: "xn--xkrr14bows.xn--fiqs8s"))
/// prints "新华网.中国"
```

Domain names are inherently case-insensitive, and they will always be lowercased.

## Implementation

This package uses Unicode 17's [IDNA test v2 suite](https://www.unicode.org/Public/idna/latest/IdnaTestV2.txt) with ~6400 test cases to ensure full compatibility.

Runs each test case extensively so each test case might even result in 2-3-4-5 test runs.

This testing facility enables the implementation to be highly optimized.
For example this packages uses `unchecked` element accessors everywhere, which do not do bounds checks.
This is only made possible thanks to the massive test suite: We expect the tests to reveal any implementation issues and incorrect element accesses.

`swift-idna` implements short-circuits in both `toASCII` and `toUnicode` functions to avoid IDNA conversions when possible.

The C code is all automatically generated using the 2 scripts in `utils/`:

- `IDNAMappingTableGenerator.swift` generates the [IDNA mapping lookup table](https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt).
- `IDNATestV2Generator.swift` generates the [IDNA test v2 suite](https://www.unicode.org/Public/idna/latest/IdnaTestV2.txt) cases to use in tests to ensure full compatibility.

#### Current supported [IDNA flags](https://www.unicode.org/reports/tr46/#Processing):

- [x] checkHyphens
- [ ] checkBidi
- [ ] checkJoiners
- [x] useSTD3ASCIIRules
- [ ] transitionalProcessing (deprecated, Unicode discourages support for this flag although it's trivial to support)
- [x] verifyDnsLength
- [x] ignoreInvalidPunycode
- [ ] replaceBadCharacters
  - This last one is not a strict part of IDNA, and is only "recommended" to implement.

## Benchmark Comparisons VS swift-foundation's ICU

* To see up to date information about performance of this package, please go to this [benchmarks list](https://github.com/swift-dns/swift-idna/actions/workflows/benchmarks.yml?query=branch%3Amain), and choose the most recent benchmark. You'll see a summary of the benchmark there.
* The results below are all reproducible by simply running `scripts/benchmark.sh` on a machine of your own.
* These were performed on a dedicated-cpu-core machine from Hetzner, on Ubuntu 24.04.
* swift-foundation applies short-circuits of its own for ascii domain names so it _should_ perform better than ICU (but likely still not as good as swift-idna).
* The benchmarks below are run in deterministically random order over multiple domains.
  * This is to simulate a real-world workload, and so the CPU can't over-fit over specific patterns.
* Last update: Jul 25, 2026

### Summary

> [!NOTE]
> * swift-idna wins 7 of the 8 benchmarks, loses 1.
> * swift-idna commits considerably less heap allocations.
> * swift-idna is much faster for the vast majority of the domain names in the wild, which are ASCII.

### ASCII Domain Names

* These are performed on 20 different ASCII domain names in [Cloudflare's top domains](https://radar.cloudflare.com/domains) list in top 50.
* 4 domain names are uppercased to account for such domains.

#### CPU Time

| Domain     | Operation  | swift-idna (ns/op) | ICU (ns/op) | Speedup |
| ---------- | ---------- | ------------------ | ----------- | ------- |
| 20 domains | To ASCII   | 26.0               | 114.0       | 4.38x   |
| 20 domains | To Unicode | 32.5               | 112.5       | 3.46x   |

#### Malloc Count

| Domain     | Operation  | swift-idna (allocs/op) | ICU (allocs/op) | Improvement |
| ---------- | ---------- | ---------------------- | --------------- | ----------- |
| 20 domains | To ASCII   | 0.05                   | 1.15            | 23x         |
| 20 domains | To Unicode | 0.05                   | 1.15            | 23x         |

### Non-ASCII Domain Names

* These are performed on all the 13 different non-ASCII domain names in [Cloudflare's top domains](https://radar.cloudflare.com/domains) list in top 50_000.

#### CPU Time

| Domain     | Operation  | swift-idna (ns/op) | ICU (ns/op) | Speedup |
| ---------- | ---------- | ------------------ | ----------- | ------- |
| 13 domains | To ASCII   | 533.3              | 566.7       | 1.06x   |
| 13 domains | To Unicode | 566.7              | 600.0       | 1.06x   |

#### Malloc Count

| Domain     | Operation  | swift-idna (allocs/op) | ICU (allocs/op) | Improvement |
| ---------- | ---------- | ---------------------- | --------------- | ----------- |
| 13 domains | To ASCII   | 2.46                   | 3.54            | 1.44x       |
| 13 domains | To Unicode | 2.62                   | 1.92            | 0.74x       |

## How To Add swift-idna To Your Project

To use the `swift-idna` library in a SwiftPM project,
add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/mahdibm/swift-idna.git", from: "1.0.0-beta.25"),
```

Include `SwiftIDNA` as a dependency for your targets:

```swift
.target(name: "<target>", dependencies: [
    .product(name: "SwiftIDNA", package: "swift-idna"),
]),
```

Finally, add `import SwiftIDNA` to your source code.

## Acknowledgments

This package was initially a part of [swift-dns](https://github.com/MahdiBM/swift-dns) which I decided to decouple from that project.
Currently it's used in [swift-endpoint](https://github.com/MahdiBM/swift-endpoint), which [swift-dns](https://github.com/MahdiBM/swift-dns) relies on.
