import SwiftIDNA
import Testing

@Suite
struct IllFormedUTF8Tests {
    static let illFormedSamples: [[UInt8]] = [
        [0x80],
        [0xBF],
        [0x61, 0x80, 0x62],
        [0xC0, 0xAF],
        [0x61, 0xC0, 0xAE, 0x62],
        [0xC1, 0xBF],
        [0xE0, 0x80, 0xAF],
        [0xE0, 0x9F, 0xBF],
        [0xF0, 0x80, 0x80, 0xAF],
        [0xF0, 0x8F, 0xBF, 0xBF],
        [0xED, 0xA0, 0x80],
        [0xED, 0xBF, 0xBF],
        [0x61, 0xED, 0xA4, 0x80, 0x7A],
        [0xF4, 0x90, 0x80, 0x80],
        [0xF5, 0x80, 0x80, 0x80],
        [0xF8, 0x88, 0x80, 0x80, 0x80],
        [0xFE],
        [0xFF],
        [0x61, 0xE4, 0x61, 0x62, 0x63],
        [0xC3, 0x61],
        [0xC3],
        [0x61, 0xE4],
        [0xE4, 0xB8],
        [0x61, 0xF0, 0x9F, 0x98],
        [UInt8](repeating: 0x61, count: 15) + [0xED, 0xA0],
        [UInt8](repeating: 0x61, count: 15) + [0xE4],
        [UInt8](repeating: 0x61, count: 40) + [0x80, 0x62],
        [0xC3, 0xA4, 0x80],
    ]

    static let wellFormedSamples: [String] = [
        "ä",
        "faß.de",
        "生命之花.中国",
        "xn--9iqv4mb85adml.xn--fiqs8s",
        "😀.com",
        "\u{D7FF}.\u{E000}",
        "\u{10FFFF}",
        "A.B",
    ]

    static func isRejectedAsIllFormedUTF8(
        _ convert: () throws(IDNA.CollectedMappingErrors) -> IDNA.ConversionResult
    ) -> Bool {
        do {
            _ = try convert()
            return false
        } catch {
            guard error.errors.count == 1,
                case .labelContainsInvalidUnicode(0xFFFD, _) = error.errors[0]
            else {
                return false
            }
            return true
        }
    }

    static func describe(
        _ domainName: String,
        _ convert: () throws(IDNA.CollectedMappingErrors) -> IDNA.ConversionResult
    ) -> String {
        do {
            return try convert().collect() ?? domainName
        } catch {
            return "\(error)"
        }
    }

    @Test(arguments: Self.illFormedSamples)
    func illFormedSpanIsRejected(bytes: [UInt8]) {
        for configuration in [IDNA.Configuration.mostStrict, .mostLax] {
            let idna = IDNA(configuration: configuration)
            bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span(_unsafeElements: buffer)
                let toUnicodeRejects = Self.isRejectedAsIllFormedUTF8 {
                    () throws(IDNA.CollectedMappingErrors) in
                    try idna.toUnicode(span: span)
                }
                let toASCIIRejects = Self.isRejectedAsIllFormedUTF8 {
                    () throws(IDNA.CollectedMappingErrors) in
                    try idna.toASCII(span: span)
                }
                #expect(toUnicodeRejects)
                #expect(toASCIIRejects)
            }
        }
    }

    @Test(arguments: Self.wellFormedSamples)
    func wellFormedSpanMatchesString(domainName: String) {
        for configuration in [IDNA.Configuration.mostStrict, .mostLax] {
            let idna = IDNA(configuration: configuration)
            let bytes = [UInt8](domainName.utf8)
            bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span(_unsafeElements: buffer)
                let toUnicodeFromSpan = Self.describe(domainName) {
                    () throws(IDNA.CollectedMappingErrors) in
                    try idna.toUnicode(span: span)
                }
                let toUnicodeFromString = Self.describe(domainName) {
                    () throws(IDNA.CollectedMappingErrors) in
                    .string(try idna.toUnicode(domainName: domainName))
                }
                let toASCIIFromSpan = Self.describe(domainName) {
                    () throws(IDNA.CollectedMappingErrors) in
                    try idna.toASCII(span: span)
                }
                let toASCIIFromString = Self.describe(domainName) {
                    () throws(IDNA.CollectedMappingErrors) in
                    .string(try idna.toASCII(domainName: domainName))
                }
                #expect(toUnicodeFromSpan == toUnicodeFromString)
                #expect(toASCIIFromSpan == toASCIIFromString)
            }
        }
    }

    func compareCheckUTF8WithStandardLibrary(
        _ bytes: UnsafeBufferPointer<UInt8>,
        length: Int,
        mismatches: inout [[UInt8]]
    ) {
        guard #available(SwiftStdlib 6.2, *) else {
            return
        }
        let prefix = unsafe UnsafeBufferPointer(rebasing: bytes[..<length])
        let span = unsafe Span(_unsafeElements: prefix)
        var isValidPerStandardLibrary = true
        do {
            _ = try UTF8Span(validating: span)
        } catch {
            isValidPerStandardLibrary = false
        }
        if span.checkUTF8() != isValidPerStandardLibrary
            || UTF8Checker.isWellFormed_SlowPath(span) != isValidPerStandardLibrary
        {
            mismatches.append(unsafe Array(prefix))
        }
    }

    @Test func checkUTF8OnEveryLeadAndSecondByte() {
        let trailingBytes: [UInt8] = [0x7F, 0x80, 0xBF, 0xC0]
        var mismatches: [[UInt8]] = []
        var bytes: [UInt8] = [0, 0, 0, 0]
        for leadByte in UInt8.min...UInt8.max {
            bytes[0] = leadByte
            bytes.withUnsafeBufferPointer { buffer in
                unsafe compareCheckUTF8WithStandardLibrary(
                    buffer,
                    length: 1,
                    mismatches: &mismatches
                )
            }
            for secondByte in UInt8.min...UInt8.max {
                bytes[1] = secondByte
                bytes.withUnsafeBufferPointer { buffer in
                    unsafe compareCheckUTF8WithStandardLibrary(
                        buffer,
                        length: 2,
                        mismatches: &mismatches
                    )
                }
                for thirdByte in trailingBytes {
                    bytes[2] = thirdByte
                    bytes.withUnsafeBufferPointer { buffer in
                        unsafe compareCheckUTF8WithStandardLibrary(
                            buffer,
                            length: 3,
                            mismatches: &mismatches
                        )
                    }
                    for fourthByte in trailingBytes {
                        bytes[3] = fourthByte
                        bytes.withUnsafeBufferPointer { buffer in
                            unsafe compareCheckUTF8WithStandardLibrary(
                                buffer,
                                length: 4,
                                mismatches: &mismatches
                            )
                        }
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    @Test func checkUTF8OnRandomizedByteStrings() {
        let alphabet: [UInt8] = [
            0x41, 0x61, 0x2D, 0x2E, 0x7F,
            0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF,
            0xC0, 0xC1, 0xC2, 0xDF,
            0xE0, 0xE1, 0xEC, 0xED, 0xEE, 0xEF,
            0xF0, 0xF1, 0xF3, 0xF4, 0xF5,
            0xFE, 0xFF,
        ]
        var mismatches: [[UInt8]] = []
        for length in 1...64 {
            for _ in 0..<300 {
                var bytes: [UInt8] = []
                bytes.reserveCapacity(length)
                for _ in 0..<length {
                    bytes.append(alphabet.randomElement()!)
                }
                bytes.withUnsafeBufferPointer { buffer in
                    unsafe compareCheckUTF8WithStandardLibrary(
                        buffer,
                        length: length,
                        mismatches: &mismatches
                    )
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    @Test func checkUTF8OnSequencesAtEveryOffset() {
        let fillers: [[UInt8]] = [
            [0x61],
            [0xC3, 0xA4],
            [0xE2, 0x82, 0xAC],
            [0xF0, 0x9F, 0x98, 0x80],
        ]
        let sequences: [[UInt8]] = [
            [0xC2, 0x80], [0xDF, 0xBF], [0xE0, 0xA0, 0x80], [0xED, 0x9F, 0xBF],
            [0xEE, 0x80, 0x80], [0xEF, 0xBF, 0xBF], [0xF0, 0x90, 0x80, 0x80],
            [0xF3, 0xBF, 0xBF, 0xBF], [0xF4, 0x8F, 0xBF, 0xBF],
            [0x80], [0xBF], [0xC0, 0x80], [0xC1, 0xBF], [0xC2, 0xC2], [0xC2, 0x41],
            [0xC2, 0x80, 0x80], [0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF], [0xE1, 0x80, 0x41],
            [0xE1, 0x80, 0x80, 0x80], [0xED, 0xA0, 0x80], [0xED, 0xBF, 0xBF],
            [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x8F, 0xBF, 0xBF], [0xF1, 0x80, 0x80, 0x41],
            [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80], [0xFF],
        ]
        var mismatches: [[UInt8]] = []
        for filler in fillers {
            for length in 1...80 {
                for offset in 0..<length {
                    for sequence in sequences {
                        var bytes = (0..<length).map { filler[$0 % filler.count] }
                        for (sequenceIdx, byte) in sequence.enumerated()
                        where offset + sequenceIdx < length {
                            bytes[offset + sequenceIdx] = byte
                        }
                        bytes.withUnsafeBufferPointer { buffer in
                            unsafe compareCheckUTF8WithStandardLibrary(
                                buffer,
                                length: length,
                                mismatches: &mismatches
                            )
                        }
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    #if !($Embedded || os(WASI))
    /// Vectors wider than 128 bits use the rows after the first, which only those targets read.
    @Test(
        arguments: [
            UTF8Checker.lookupByte1High,
            UTF8Checker.lookupByte1Low,
            UTF8Checker.lookupByte2High,
        ]
    )
    func utf8LookupTableRepeatsPer128Bits(table: [UInt8]) {
        let firstRow = Array(table[0..<16])
        for rowStart in stride(from: 16, to: table.count, by: 16) {
            #expect(Array(table[rowStart..<(rowStart + 16)]) == firstRow)
        }
    }
    #endif
}
