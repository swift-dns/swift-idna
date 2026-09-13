import Foundation
import SwiftIDNA
import Testing

@Suite
struct NFCTests {
    static func normalized(_ bytes: [UInt8]) -> [UInt8] {
        bytes.withUnsafeBufferPointer { bytesPtr in
            let span = unsafe bytesPtr.span
            return NFCNormalization.withNFCNormalized(span) { outputSpan in
                unsafe [UInt8](
                    unsafeUninitializedCapacity: outputSpan.count
                ) { buffer, initializedCount in
                    for idx in outputSpan.indices {
                        unsafe buffer[idx] = outputSpan[idx]
                    }
                    initializedCount = outputSpan.count
                }
            }
        }
    }

    static func quickCheck(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { bytesPtr in
            NFCNormalization.quickCheck(unsafe bytesPtr.span)
        }
    }

    static func utf8(_ scalars: [UInt32]) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(scalars.count * 4)
        for scalar in scalars {
            bytes.append(contentsOf: Array(Unicode.Scalar(scalar)!.utf8))
        }
        return bytes
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Exhaustive ccc cross-check against the stdlib`() {
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let expectedCCC = UInt16(scalar.properties.canonicalCombiningClass.rawValue)
            let info = NFCScalarInfo.for(scalar: value)
            let matches: Bool
            switch info.tag {
            case .cccOnly:
                matches = info.payload == expectedCCC && expectedCCC != 0
            case .maybe:
                matches = info.payload == expectedCCC
            case .inert, .decompositionQCYes, .maybeWithDecomposition, .hangulSyllable:
                matches = expectedCCC == 0
            case .decompositionQCNo:
                /// The trie intentionally does not store the standalone ccc of NFC_QC=No
                /// scalars; their ccc is only ever consulted through decomposition elements,
                /// which the exhaustive NFC differential test exercises.
                matches = true
            }
            if !matches {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(mismatches.isEmpty, "ccc mismatches at \(mismatches.map { String($0, radix: 16) })")
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Exhaustive per-scalar NFC differential against Foundation`() {
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let string = String(scalar)
            let expected = Array(string.precomposedStringWithCanonicalMapping.utf8)
            let composedInput = Self.normalized(Array(string.utf8))
            let decomposedInput = Self.normalized(
                Array(string.decomposedStringWithCanonicalMapping.utf8)
            )
            if composedInput != expected || decomposedInput != expected {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(mismatches.isEmpty, "NFC mismatches at \(mismatches.map { String($0, radix: 16) })")
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Exhaustive per-scalar quick check soundness`() {
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let bytes = Array(String(scalar).utf8)
            if Self.quickCheck(bytes), Self.normalized(bytes) != bytes {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(
            mismatches.isEmpty,
            "quick check false positives at \(mismatches.map { String($0, radix: 16) })"
        )
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Exhaustive Hangul syllable decomposition round-trip`() {
        var mismatches: [UInt32] = []
        for value in UInt32(0xAC00)...0xD7A3 {
            let syllable = Self.utf8([value])
            let jamo = Array(
                String(Unicode.Scalar(value)!).decomposedStringWithCanonicalMapping.utf8
            )
            if Self.normalized(jamo) != syllable || Self.normalized(syllable) != syllable {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(
            mismatches.isEmpty,
            "Hangul mismatches at \(mismatches.map { String($0, radix: 16) })"
        )
    }

    @available(SwiftStdlib 6.2, *)
    @Test(
        arguments: [
            /// Composition-excluded scalars stay decomposed, expanding their UTF-8.
            (input: [0x0958], nfc: [0x0915, 0x093C]),
            (
                input: [0x0958, 0x0958, 0x0958, 0x0958, 0x0958, 0x0958, 0x0958, 0x0958],
                nfc: [
                    0x0915, 0x093C, 0x0915, 0x093C, 0x0915, 0x093C, 0x0915, 0x093C,
                    0x0915, 0x093C, 0x0915, 0x093C, 0x0915, 0x093C, 0x0915, 0x093C,
                ]
            ),
            /// Singleton decompositions.
            (input: [0x2126], nfc: [0x03A9]),
            (input: [0x212B], nfc: [0x00C5]),
            /// Two-way composition from decomposed input.
            (input: [0x0041, 0x0300], nfc: [0x00C0]),
            /// Multi-level composition through an intermediate composite.
            (input: [0x0041, 0x0302, 0x0301], nfc: [0x1EA4]),
            (input: [0x0045, 0x0304, 0x0301], nfc: [0x1E16]),
            /// Reordering then composition: the below-mark sorts before the above-marks.
            (input: [0x0061, 0x0301, 0x0323], nfc: [0x1EA1, 0x0301]),
            /// Blocked composition: an intervening mark with an equal ccc blocks the second mark.
            (input: [0x0061, 0x0305, 0x0300], nfc: [0x0061, 0x0305, 0x0300]),
            /// Not blocked: a lower-ccc mark in between does not block.
            (input: [0x0061, 0x0323, 0x0300], nfc: [0x1EA1, 0x0300]),
            /// A non-pairing Maybe scalar stays as-is.
            (input: [0x0078, 0x0301], nfc: [0x0078, 0x0301]),
            /// Non-starter decomposition. The dialytika composes first as it comes first in
            /// the stream, then the tonos finds no pair with the composite.
            (input: [0x0344], nfc: [0x0308, 0x0301]),
            (input: [0x0061, 0x0344], nfc: [0x00E4, 0x0301]),
            /// Hangul from partial jamo sequences.
            (input: [0x1100, 0x1161], nfc: [0xAC00]),
            (input: [0x1100, 0x1161, 0x11A8], nfc: [0xAC01]),
            (input: [0xAC00, 0x11A8], nfc: [0xAC01]),
            /// LVT syllables do not compose with another trailing jamo.
            (input: [0xAC01, 0x11A8], nfc: [0xAC01, 0x11A8]),
            /// Lone jamo stay as-is.
            (input: [0x1161], nfc: [0x1161]),
            (input: [0x11A8], nfc: [0x11A8]),
            /// Leading combining marks without a starter.
            (input: [0x0301, 0x0300], nfc: [0x0301, 0x0300]),
            (input: [0x0323, 0x0301], nfc: [0x0323, 0x0301]),
            /// Code points at or above the trie limit are inert.
            (input: [0x30000], nfc: [0x30000]),
            (input: [0x10FFFF], nfc: [0x10FFFF]),
            /// Degenerate inputs.
            (input: [], nfc: []),
            (input: [0x0061, 0x0062, 0x0063], nfc: [0x0061, 0x0062, 0x0063]),
        ] as [(input: [UInt32], nfc: [UInt32])]
    )
    func `Hand-written normalization edge cases`(
        _ testCase: (input: [UInt32], nfc: [UInt32])
    ) {
        /// The expected values are authoritative per UAX #15; Foundation is deliberately not
        /// consulted here because its `precomposedStringWithCanonicalMapping` deviates from
        /// the standard on Hangul LV+T composition. The generated NormalizationTest.txt
        /// conformance suite is the anchor for these sequences.
        let input = Self.utf8(testCase.input)
        let expected = Self.utf8(testCase.nfc)
        #expect(Self.normalized(input) == expected)

        /// Idempotence: normalizing NFC output must be a no-op.
        #expect(Self.normalized(expected) == expected)

        /// The quick check must never claim a non-NFC input is NFC.
        if input != expected {
            #expect(!Self.quickCheck(input))
        }
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `MaybeNo composites are tagged maybeWithDecomposition`() {
        let maybeNoComposites: [UInt32] = [
            0x113C5, 0x113C7, 0x113C8,
            0x16121, 0x16122, 0x16123, 0x16124, 0x16125, 0x16126, 0x16127, 0x16128,
            0x16D68,
        ]
        for scalar in maybeNoComposites {
            let info = NFCScalarInfo.for(scalar: scalar)
            #expect(
                info.tag == .maybeWithDecomposition,
                "U+\(String(scalar, radix: 16, uppercase: true)) has tag \(info.tag)"
            )
            let bytes = Self.utf8([scalar])
            #expect(Self.normalized(bytes) == bytes)
            #expect(!Self.quickCheck(bytes))
        }
    }

    @available(SwiftStdlib 6.2, *)
    @Test(arguments: NFCTestCase.enumeratedAllCases())
    func `Unicode normalization conformance suite`(
        _ enumeratedTestCase: (index: Int, case: NFCTestCase)
    ) {
        let testCase = enumeratedTestCase.case

        /// c2 == toNFC(c1) == toNFC(c2) == toNFC(c3)
        #expect(Self.normalized(testCase.c1) == testCase.c2)
        #expect(Self.normalized(testCase.c2) == testCase.c2)
        #expect(Self.normalized(testCase.c3) == testCase.c2)
        /// c4 == toNFC(c4) == toNFC(c5)
        #expect(Self.normalized(testCase.c4) == testCase.c4)
        #expect(Self.normalized(testCase.c5) == testCase.c4)

        /// The quick check must never claim a non-NFC column is NFC.
        if testCase.c1 != testCase.c2 {
            #expect(!Self.quickCheck(testCase.c1))
        }
        if testCase.c3 != testCase.c2 {
            #expect(!Self.quickCheck(testCase.c3))
        }
        if testCase.c5 != testCase.c4 {
            #expect(!Self.quickCheck(testCase.c5))
        }
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Scalars not listed in conformance suite Part 1 normalize to themselves`() {
        let listed = NFCTestCase.part1ListedScalars()
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            if listed.contains(value) { continue }
            let bytes = Array(String(scalar).utf8)
            if Self.normalized(bytes) != bytes {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(
            mismatches.isEmpty,
            "unlisted scalars not normalizing to themselves: \(mismatches.map { String($0, radix: 16) })"
        )
    }

    @available(SwiftStdlib 6.2, *)
    @Test func `Quick check accepts plain inputs`() {
        #expect(Self.quickCheck([]))
        #expect(Self.quickCheck(Array("example.com".utf8)))
        #expect(Self.quickCheck(Self.utf8([0x00E9, 0x00E8, 0x01D5])))
        #expect(Self.quickCheck(Self.utf8([0xAC00, 0xD7A3])))
        #expect(Self.quickCheck(Self.utf8([0x30000, 0x10FFFF])))
    }
}
