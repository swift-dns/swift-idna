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
