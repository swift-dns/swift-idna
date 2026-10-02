import SwiftIDNA
import Testing

@Suite
struct DecoderWindowEquivalenceTests {
    /// Walks every window of `bytes` and checks that whatever path
    /// `decodeNextWindow` picked agrees exactly with the plain chain walk.
    func checkAllWindows(_ bytes: [UInt8], _ label: @autoclosure () -> String) {
        let count = bytes.count
        guard count > 0 else { return }
        bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span(_unsafeElements: buffer)
            SIMDUnicodeScalarDecoder.withTemporaryDecoder { decoder in
                var startIdx = 0
                while startIdx < count {
                    decoder.decodeNextWindow(of: span, startIdx: startIdx)

                    /// Every position must decode exactly as `UnicodeScalarIterator.decodeScalar`.
                    let lengthsPadding =
                        decoder.paddedScalarUTF8Lengths.count &- SIMDUnicodeScalarDecoder.windowSize
                    var expectedLengths: [UInt8] = []
                    var decodedLengths: [UInt8] = []
                    var expectedScalars: [UInt32] = []
                    var decodedScalars: [UInt32] = []
                    for idx in 0..<SIMDUnicodeScalarDecoder.windowSize {
                        let leadByte = decoder.tempBytes[idx]
                        let leadingOnes = Swift.min(4, (~leadByte).leadingZeroBitCount)
                        let scalarUTF8Length = Swift.max(1, leadingOnes)
                        let leadNoLengthBits =
                            UInt32(leadByte & (0b0111_1111 &>> leadingOnes)) &<< 18
                        let c1 = UInt32(decoder.tempBytes[idx &+ 1] & 0b0011_1111) &<< 12
                        let c2 = UInt32(decoder.tempBytes[idx &+ 2] & 0b0011_1111) &<< 6
                        let c3 = UInt32(decoder.tempBytes[idx &+ 3] & 0b0011_1111)
                        let shift = 6 &* (4 &- scalarUTF8Length)
                        expectedLengths.append(UInt8(scalarUTF8Length))
                        expectedScalars.append((leadNoLengthBits | c1 | c2 | c3) &>> shift)
                        decodedLengths.append(
                            decoder.paddedScalarUTF8Lengths[lengthsPadding &+ idx]
                        )
                        decodedScalars.append(decoder.uncheckedScalarValues[idx])
                    }
                    #expect(decodedLengths == expectedLengths, "\(label()) at startIdx \(startIdx)")
                    #expect(decodedScalars == expectedScalars, "\(label()) at startIdx \(startIdx)")

                    var chosen: [UInt8] = []
                    for idx in 0...decoder.scalarCount {
                        chosen.append(decoder.scalarStartOffsets[idx])
                    }

                    let windowLength = Swift.min(
                        SIMDUnicodeScalarDecoder.windowSize,
                        count &- startIdx
                    )
                    decoder.chainScalarStarts(windowLength: windowLength)

                    var chained: [UInt8] = []
                    for idx in 0...decoder.scalarCount {
                        chained.append(decoder.scalarStartOffsets[idx])
                    }

                    #expect(chosen == chained, "\(label()) at startIdx \(startIdx)")

                    startIdx &+= Int(chained[chained.count &- 1])
                }
            }
        }
    }

    @Test func exhaustiveFourByteStrings() {
        let alphabet: [UInt8] = [
            0x41, 0x2E, 0x7F,
            0x80, 0xBF,
            0xC2, 0xDF,
            0xE0, 0xEF,
            0xF0, 0xF4,
            0xFF,
        ]
        for a in alphabet {
            for b in alphabet {
                for c in alphabet {
                    for d in alphabet {
                        let bytes: [UInt8] = [a, b, c, d]
                        checkAllWindows(bytes, "\(bytes)")
                    }
                }
            }
        }
    }

    @Test func everyLeadAndContinuationBytePair() {
        let continuationBytes2And3: [(UInt8, UInt8)] = [
            (0x80, 0xBF),
            (0xBF, 0x80),
            (0x3F, 0xC0),
            (0xFF, 0x00),
        ]
        var bytes: [UInt8] = []
        for leadByte in UInt8.min...UInt8.max {
            for continuationByte1 in UInt8.min...UInt8.max {
                for (continuationByte2, continuationByte3) in continuationBytes2And3 {
                    bytes += [leadByte, continuationByte1, continuationByte2, continuationByte3]
                }
            }
        }
        checkAllWindows(bytes, "every lead and continuation byte pair")
    }

    @Test func randomizedLongByteStrings() {
        let alphabet: [UInt8] = [
            0x41, 0x61, 0x2D, 0x2E, 0x30, 0x7F,
            0x80, 0x9F, 0xBF,
            0xC2, 0xC3, 0xCC, 0xDF,
            0xE0, 0xE1, 0xE3, 0xED, 0xEF,
            0xF0, 0xF3, 0xF4, 0xF5,
            0xFD, 0xFE, 0xFF,
        ]
        var generator = SystemRandomNumberGenerator()
        for length in 1...120 {
            for _ in 0..<500 {
                var bytes: [UInt8] = []
                bytes.reserveCapacity(length)
                for _ in 0..<length {
                    bytes.append(alphabet.randomElement(using: &generator)!)
                }
                checkAllWindows(bytes, "\(bytes)")
            }
        }
    }

    @Test func mostlyValidUTF8WithCorruption() {
        let samples = [
            "日本語のドメイン名テストです",
            "أمثلة-اختبار-النطاق-العربي",
            "Ｅｘａｍｐｌｅ-ＦＵＬＬＷＩＤＴＨ-ｔｅｓｔ",
            "𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏𝕏",
            "a𝕏b日ｃ😀d語e𝕏f",
            "ⅨⅩⅪ-ﬀﬁﬂ-ǅǆǇ",
        ]
        var generator = SystemRandomNumberGenerator()
        for sample in samples {
            let full = Array(sample.utf8)
            for prefixLength in 0...20 {
                let padded = Array(repeating: UInt8(0x61), count: prefixLength) + full
                for length in 1...padded.count {
                    checkAllWindows(
                        Array(padded[0..<length]),
                        "\(sample) +\(prefixLength) /\(length)"
                    )
                }
            }
            for _ in 0..<20_000 {
                var bytes = full
                let idx = Int.random(in: 0..<bytes.count, using: &generator)
                bytes[idx] = UInt8.random(in: 0...255, using: &generator)
                checkAllWindows(bytes, "\(sample) corrupted at \(idx)")
            }
        }
    }
}
