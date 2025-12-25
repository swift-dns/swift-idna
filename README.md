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
    <a href="https://swift.org">
        <img
            src="https://design.vapor.codes/images/swift623up.svg"
            alt="Swift 6.2.3+"
        >
    </a>
</p>

# swift-idna

A high-perfomance, multiplatform implementation of Punycode and IDNA (Internationalized Domain Names in Applications) as per [RFC 5891](https://datatracker.ietf.org/doc/html/rfc5891) and friends.

The only dependency of `swift-idna` is `swift-collections`, and it does not depend on `Foundation`.

## Usage

Initialize `IDNA` with your preffered configuration, then use `toASCII(domainName:)` and `toUnicode(domainName:)`:

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

## Short Circuits

`swift-idna` does short-circuit checks in both `toASCII` and `toUnicode` functions to avoid IDNA conversions when possible.

`swift-idna` also provides public functions to check if a sequence of bytes will change at all after going through IDNA's `ToASCII` conversion.

Note that these public functions are not sufficient to assert that a `ToUnicode` conversion will also have no effect on the string.
For `ToUnicode`, simply use the `toUnicode` functions and they will automatically skip the conversion if not needed.

- `IDNA.performByteCheck(on: String)`
- `IDNA.performByteCheck(on: Substring)`
- `IDNA.performByteCheck(on: Span<UInt8>)`
- `IDNA.performByteCheck(onDNSWireFormatSpan: Span<UInt8>)`

`swift-idna` also provides public functions to turn an uppercased ASCII byte into lowercased, as well as a few more useful functions.

- `BinaryInteger.toLowercasedASCIILetter()`
- `BinaryInteger._uncheckedToLowercasedASCIILetterAssumingUppercasedLetter()`
- `BinaryInteger.isUppercasedASCIILetter`
- `BinaryInteger.isIDNALabelSeparator`

To use this on a `Unicode.Scalar`, simply use them on `Unicode.Scalar`'s `value` property.

You can use these function to implement short-circuits for any reason.

For example if you only have a sequence of bytes and don't want to decode them into a `String` to provide to this library, considering this library only accepts Swift `String`s as domain names.

Example usage:

```swift
import SwiftIDNA

let myBytes: [UInt8] = ...

switch IDNA.performCharacterCheck(on: myBytes.span) {
case .containsOnlyIDNANoOpCharacters:
    /// `myBytes` is good
case .onlyNeedsLowercasingOfUppercasedASCIILetters:
    myBytes = myBytes.map {
        $0.toLowercasedASCIILetter()
    }
    /// `myBytes` is good now
case .mightChangeAfterIDNAConversion:
    /// Need to go through IDNA conversion functions if needed
}
```

## Implementation

This package uses Unicode 17's [IDNA test v2 suite](https://www.unicode.org/Public/idna/latest/IdnaTestV2.txt) with ~6400 test cases to ensure full compatibility.

Runs each test case extensively so each test case might even result in 2-3-4-5 test runs.

This testing facility enables the implementation to be highly optimized.   
For example this packages uses `unchecked` element accessors everywhere, which do not do bounds checks.   
This is only made possible thanks to the massive test suite: We expect the tests to reveal any implementation issues and incorrect element accesses.

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
