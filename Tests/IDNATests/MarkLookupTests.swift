import SwiftIDNA
import Testing

@Suite
struct MarkLookupTests {
    /// The lookup table is generated from Unicode 18.0, which gave these code points to
    /// General_Category=Mark. No released stdlib carries Unicode 18 data yet, so it still
    /// reports them as unassigned. Drop them here once the stdlib catches up.
    static let unicode18MarkAdditions: Set<UInt32> = Set(
        [
            0x5C8...0x5C9,
            0xB53...0xB54,
            0x1ADE...0x1ADF,
            0x1AEC...0x1AF0,
            0x10ECB...0x10ECF,
            0x10EF0...0x10EF9,
            0x11DF0...0x11DF0,
            0x1D127...0x1D128,
            0x1D250...0x1D252,
            0x1D25B...0x1D25C,
            0x1D25F...0x1D25F,
            0x1D280...0x1D281,
        ].joined()
    )

    @Test func `swift-idna mark info agrees with stdlib`() throws {
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10_FFFF {
            guard let scalar = UnicodeScalarValue(value) else { continue }
            if Self.unicode18MarkAdditions.contains(value) { continue }
            let stdlibScalar = try #require(Unicode.Scalar(scalar.value))
            /// Unicode 17.0 gave U+1ACF...U+1ADD to combining marks. macOS 15 still has them unassigned.
            if #unavailable(SwiftStdlib 6.2) {
                if stdlibScalar.properties.generalCategory == .unassigned { continue }
            }
            let expected = stdlibScalar.isMark
            if scalar.isMark != expected {
                mismatches.append(value)
                if mismatches.count > 10 { break }
            }
        }
        #expect(
            mismatches.isEmpty,
            "isMark mismatches at \(mismatches.map { String($0, radix: 16, uppercase: true) })"
        )
    }

    @Test func `The only combining marks beyond the lookup table are variation selectors`() {
        #expect(UnicodeScalarValue(0xE0100)!.isMark)
        #expect(UnicodeScalarValue(0xE01EF)!.isMark)
        #expect(!UnicodeScalarValue(0xE00FF)!.isMark)
        #expect(!UnicodeScalarValue(0xE01F0)!.isMark)
        #expect(!UnicodeScalarValue(0x10_FFFF)!.isMark)
    }
}

extension Unicode.Scalar {
    var isMark: Bool {
        switch self.properties.generalCategory {
        case .spacingMark, .enclosingMark, .nonspacingMark:
            return true
        default:
            return false
        }
    }
}
