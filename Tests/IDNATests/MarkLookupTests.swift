import SwiftIDNA
import Testing

@Suite
struct MarkLookupTests {
    @Test func `swift-idna mark info agrees with stdlib`() throws {
        var mismatches: [UInt32] = []
        for value in UInt32(0)...0x10_FFFF {
            guard let scalar = UnicodeScalarValue(value) else { continue }
            let stdlibScalar = try #require(Unicode.Scalar(scalar.value))
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
