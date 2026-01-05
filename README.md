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
            src="https://design.vapor.codes/images/swift623up.svg"
            alt="Swift 6.2.3+"
        >
    </a>
</p>

# swift-idna

A high performance, highly optimized multi-platform implementation of Punycode and IDNA (Internationalized Domain Names in Applications) as per [RFC 5891](https://datatracker.ietf.org/doc/html/rfc5891) and friends.

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
* The results below are all reproducible by simply running `scripts/benchmark.bash` on a machine of your own.
* swift-foundation applies short-circuits of its own for ascii domain names so it _should_ perform better than ICU (but likely still not as good as swift-idna).

### Summary

> [!NOTE]
> **swift-idna** wins the **Malloc count** benchmarks by far.  
> **ICU** wins the **Non-ASCII Domain Names** CPU time, by a bit.  
> **swift-idna** wins **ASCII Domain Names** CPU time by far.  

### Non-ASCII Domain Names

#### CPU Time

Benchmark | Foundation | swift-idna | Improv. Ratio
| -- | -- | -- | --
To_ASCII_Lax_öob_dot_se_CPU_300K | 80ms | 80ms | 1x
To_ASCII_Lax_生命之花_dot_中国_CPU_200K | 80ms | 120ms | 0.67x
To_Unicode_Lax_öob_dot_se_CPU_300K | 100ms | 80ms | 1.25x
To_Unicode_Lax_生命之花_dot_中国_CPU_200K | 110ms | 110ms | 1x

#### Malloc Count

Benchmark | Foundation | swift-idna | Improv. Ratio
| -- | -- | -- | --
To_ASCII_Lax_öob_dot_se_Malloc | 2 | 1 | 2x
To_ASCII_Lax_生命之花_dot_中国_Malloc | 5 | 4 | 1.25x
To_Unicode_Lax_öob_dot_se_Malloc | 1 | 1 | 1x
To_Unicode_Lax_生命之花_dot_中国_Malloc | 4 | 3 | 1.33x

### ASCII Domain Names

#### CPU Time

Benchmark | Foundation | swift-idna | Improv. Ratio
| -- | -- | -- | --
To_ASCII_Lowercased_app-analytics-services_dot_com_CPU_5M | 610ms | 140ms | 4.36x
To_ASCII_Lowercased_google_dot_com_CPU_8M | 650ms | 180ms | 3.61x
To_ASCII_Uppercased_app-analytics-services_dot_com_CPU_3M | 340ms | 180ms | 1.89x
To_ASCII_Uppercased_google_dot_com_CPU_5M | 380ms | 140ms | 2.71x
To_Unicode_Lowercased_app-analytics-services_dot_com_CPU_4M | 470ms | 170ms | 2.76x
To_Unicode_Lowercased_google_dot_com_CPU_8M | 650ms | 230ms | 2.83x
To_Unicode_Uppercased_app-analytics-services_dot_com_CPU_4M | 440ms | 250ms | 1.76x
To_Unicode_Uppercased_google_dot_com_CPU_5M | 380ms | 180ms | 2.11x

#### Malloc Count

Benchmark | Foundation | swift-idna | Improv. Ratio
| -- | -- | -- | --
To_ASCII_Lowercased_app-analytics-services_dot_com_Malloc | 2 | 0 | ∞
To_ASCII_Lowercased_google_dot_com_Malloc | 1 | 0 | ∞
To_ASCII_Uppercased_app-analytics-services_dot_com_Malloc | 2 | 1 | 2x
To_ASCII_Uppercased_google_dot_com_Malloc | 1 | 0 | ∞
To_Unicode_Lowercased_app-analytics-services_dot_com_Malloc | 2 | 0 | ∞
To_Unicode_Lowercased_google_dot_com_Malloc | 1 | 0 | ∞
To_Unicode_Uppercased_app-analytics-services_dot_com_Malloc | 2 | 1 | 2x
To_Unicode_Uppercased_google_dot_com_Malloc | 1 | 0 | ∞

## How To Add swift-idna To Your Project

To use the `swift-idna` library in a SwiftPM project,
add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/mahdibm/swift-idna.git", from: "1.0.0-beta.15"),
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
