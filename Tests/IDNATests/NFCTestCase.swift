import CSwiftIDNATesting

/// Represents a single test case from the Unicode Normalization Conformance Test suite:
/// https://www.unicode.org/Public/UCD/latest/ucd/NormalizationTest.txt
///
/// The columns are `source; NFC; NFD; NFKC; NFKD`, and the NFC conformance invariants are:
/// ```text
/// c2 == toNFC(c1) == toNFC(c2) == toNFC(c3)
/// c4 == toNFC(c4) == toNFC(c5)
/// ```
/// Additionally, every code point not listed in the first column of Part 1 must satisfy
/// `X == toNFC(X)`.
struct NFCTestCase {
    let c1: [UInt8]
    let c2: [UInt8]
    let c3: [UInt8]
    let c4: [UInt8]
    let c5: [UInt8]
    let part: Int

    init(from cCase: CSwiftIDNANFCTestCCase) {
        self.c1 = unsafe Self.toUInt8Array(cCase.c1, count: cCase.c1Count)
        self.c2 = unsafe Self.toUInt8Array(cCase.c2, count: cCase.c2Count)
        self.c3 = unsafe Self.toUInt8Array(cCase.c3, count: cCase.c3Count)
        self.c4 = unsafe Self.toUInt8Array(cCase.c4, count: cCase.c4Count)
        self.c5 = unsafe Self.toUInt8Array(cCase.c5, count: cCase.c5Count)
        self.part = unsafe Int(cCase.part)
    }

    private static func toUInt8Array(_ cString: UnsafePointer<CChar>, count: Int) -> [UInt8] {
        let buffer = unsafe UnsafeBufferPointer(start: cString, count: count)
        return unsafe buffer.withMemoryRebound(to: UInt8.self) {
            unsafe Array($0)
        }
    }

    static func allCases() -> [NFCTestCase] {
        var count: Int = 0
        guard let ptr = unsafe cswift_idna_nfc_test_all_cases(&count) else {
            fatalError("Failed to get NFC test cases")
        }
        return (0..<count).map { i in unsafe NFCTestCase(from: ptr[i]) }
    }

    /// This is better for debuggability.
    /// If a certain case is failing, we'll know what index it belongs to so we can
    /// try to investigate that case alone.
    static func enumeratedAllCases() -> [(index: Int, case: NFCTestCase)] {
        Self.allCases().enumerated().map { ($0, $1) }
    }

    /// The set of scalars listed in the first column of Part 1, which is exactly the set of
    /// scalars the conformance suite exempts from the `X == toNFC(X)` invariant.
    static func part1ListedScalars() -> Set<UInt32> {
        var listed = Set<UInt32>()
        for testCase in Self.allCases() where testCase.part == 1 {
            let scalars = String(decoding: testCase.c1, as: UTF8.self).unicodeScalars
            guard scalars.count == 1 else {
                fatalError("Part1 case with a multi-scalar first column")
            }
            listed.insert(scalars.first!.value)
        }
        return listed
    }
}

extension NFCTestCase: CustomStringConvertible {
    var description: String {
        func hexScalars(_ bytes: [UInt8]) -> String {
            String(decoding: bytes, as: UTF8.self).unicodeScalars.map {
                String($0.value, radix: 16, uppercase: true)
            }.joined(separator: " ")
        }
        return
            "NFCTestCase(part: \(part), c1: \(hexScalars(c1)), c2: \(hexScalars(c2)), c3: \(hexScalars(c3)), c4: \(hexScalars(c4)), c5: \(hexScalars(c5)))"
    }
}
