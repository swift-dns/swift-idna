import SwiftIDNA
import Testing

@Suite
struct IDNAMappingLookupTests {
    @Test func nonScalarValuesAreIgnored() {
        /// Every surrogate and everything above `0x10FFFF` a UTF-8 decode can produce, plus the
        /// far end of the `UInt32` range the signature allows.
        var probes = Array(UInt32(0xD800)...0xDFFF)
        probes.append(contentsOf: (0x11_0000 as UInt32)...0x1F_FFFF)
        probes.append(contentsOf: [0x20_0000, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFE, .max])

        for value in probes {
            #expect(Unicode.Scalar(value) == nil)
            let mapping = IDNAMapping.for(uncheckedScalar: value)
            #expect(
                mapping.tag == .ignored,
                "U+\(String(value, radix: 16, uppercase: true)) -> \(mapping.tag)"
            )
        }
    }

    @Test func scalarNeighboursOfTheSurrogateBlockAreUnaffected() {
        #expect(IDNAMapping.for(uncheckedScalar: 0xD7FF).tag == .disallowed)
        #expect(IDNAMapping.for(uncheckedScalar: 0xE000).tag == .disallowed)
        #expect(IDNAMapping.for(uncheckedScalar: 0x10_FFFF).tag == .disallowed)
    }

    @Test func agreesWithCheckedLookupForEveryValidScalar() {
        for value in UInt32(0)...0x10_FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            #expect(
                IDNAMapping.for(scalar: scalar).tag
                    == IDNAMapping.for(uncheckedScalar: value).tag,
                "U+\(String(value, radix: 16, uppercase: true))"
            )
        }
    }
}
