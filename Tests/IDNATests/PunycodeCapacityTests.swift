import BasicContainers
import SwiftIDNA
import Testing

@Suite
struct PunycodeCapacityTests {
    /// `Punycode.encode` appends into `outputBufferForReuse` without ever reserving capacity,
    /// so a label whose encoded form outgrows the stack seed must have spilled over to the heap
    /// rather than been written past the end of the stack allocation.
    @Test(arguments: 1...40)
    func encodedLabelStaysWithinTheBuffer(asciiCount: Int) {
        let input = Array((String(repeating: "a", count: asciiCount) + "\u{00E9}").utf8)
        let (capacity, count, encoded) = input.withUnsafeBufferPointer {
            raw -> (Int, Int, String) in
            let span = unsafe raw.span
            var errors = IDNA.MappingErrors(domainNameSpan: span)
            var base = DecodedUnicodeScalars(utf8Bytes: span, errors: &errors)
            var scalars = DecodedUnicodeScalars.Subsequence(base: &base)
            scalars.set(utf8OffsetRange: unsafe Range(uncheckedBounds: (0, span.count)))
            return withIDNATemporaryBuffer { output -> (Int, Int, String) in
                Punycode.encode(
                    inputBytesSpan: span,
                    outputBufferForReuse: &output,
                    decodedUnicodeScalars: scalars
                )
                let encoded = output.span
                var text = ""
                for idx in encoded.indices {
                    text.unicodeScalars.append(Unicode.Scalar(encoded[idx]))
                }
                return (output.capacity, encoded.count, text)
            }
        }

        #expect(
            count <= capacity,
            "wrote \(count) bytes into a buffer of \(capacity)"
        )
        if count > TEMPORARY_ARRAY__STACK_SEED_CAPACITY {
            #expect(
                capacity > TEMPORARY_ARRAY__STACK_SEED_CAPACITY,
                "\(count) bytes did not spill the \(TEMPORARY_ARRAY__STACK_SEED_CAPACITY) byte stack seed"
            )
        }
        #expect(encoded == Self.referenceEncodings[asciiCount])
    }

    /// Punycode of `"a" * asciiCount + "\u{00E9}"`, per RFC 3492.
    static let referenceEncodings: [Int: String] = [
        1: "a-bga",
        2: "aa-cja",
        3: "aaa-dma",
        4: "aaaa-epa",
        5: "aaaaa-fsa",
        6: "aaaaaa-gva",
        7: "aaaaaaa-hya",
        8: "aaaaaaaa-i1a",
        9: "aaaaaaaaa-j4a",
        10: "aaaaaaaaaa-k7a",
        11: "aaaaaaaaaaa-lbb",
        12: "aaaaaaaaaaaa-meb",
        13: "aaaaaaaaaaaaa-nhb",
        14: "aaaaaaaaaaaaaa-okb",
        15: "aaaaaaaaaaaaaaa-pnb",
        16: "aaaaaaaaaaaaaaaa-qqb",
        17: "aaaaaaaaaaaaaaaaa-rtb",
        18: "aaaaaaaaaaaaaaaaaa-swb",
        19: "aaaaaaaaaaaaaaaaaaa-tzb",
        20: "aaaaaaaaaaaaaaaaaaaa-u2b",
        21: "aaaaaaaaaaaaaaaaaaaaa-v5b",
        22: "aaaaaaaaaaaaaaaaaaaaaa-w8b",
        23: "aaaaaaaaaaaaaaaaaaaaaaa-xcc",
        24: "aaaaaaaaaaaaaaaaaaaaaaaa-yfc",
        25: "aaaaaaaaaaaaaaaaaaaaaaaaa-zic",
        26: "aaaaaaaaaaaaaaaaaaaaaaaaaa-0lc",
        27: "aaaaaaaaaaaaaaaaaaaaaaaaaaa-1oc",
        28: "aaaaaaaaaaaaaaaaaaaaaaaaaaaa-2rc",
        29: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaa-3uc",
        30: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-4xc",
        31: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-50c",
        32: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-63c",
        33: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-76c",
        34: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-89c",
        35: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-9dd",
        36: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bhd",
        37: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-ckd",
        38: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-dnd",
        39: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-eqd",
        40: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-ftd",
    ]
}
