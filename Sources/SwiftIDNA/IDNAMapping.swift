public import CSwiftIDNA

@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct IDNAMapping {
    @usableFromInline
    package enum Tag: UInt16 {
        case validNone = 0
        case validNV8 = 1
        case validXV8 = 2
        case ignored = 3
        case disallowed = 4
        case deviation = 5
        case mapped = 6
    }

    @usableFromInline
    package let tag: Tag
    /// Only valid for `mapped` and `deviation` tags. Otherwise an invalid value.
    /// We don't guard access to it with e.g. an assert because again
    /// the tests are exhaustive and they'd fail anyway.
    @usableFromInline
    package let mappedScalars: IDNAUnicodeScalarView

    @inlinable
    init(packedValue: UInt16) {
        /// This is exhaustively tested, so `unsafelyUnwrapped` is safe.
        self.tag = unsafe Tag(rawValue: packedValue >> 13).unsafelyUnwrapped
        /// If there is no payload (!mapped && !deviation) then `sliceIndex` always amounts to 0.
        let sliceIndex = UInt32(packedValue & 0x1FFF)
        let slice = cswift_idna_mapped_slice(sliceIndex)
        let payloadPtr = unsafe cswift_idna_mapped_utf8_at(slice >> 8)
        let payloadCount = Int(slice & 0xFF)
        self.mappedScalars = unsafe IDNAUnicodeScalarView(
            staticPointer: UnsafeBufferPointer(
                start: payloadPtr,
                count: payloadCount
            )
        )
    }
}

@available(SwiftStdlib 5.1, *)
extension IDNAMapping {
    /// Look up IDNA mapping for a given Unicode scalar.
    /// - Parameter scalar: The Unicode scalar to look up
    /// - Returns: The corresponding `IDNAMapping` value
    @inlinable
    package static func `for`(scalar: Unicode.Scalar) -> IDNAMapping {
        IDNAMapping(packedValue: cswift_idna_packed_value(scalar.value))
    }

    /// Look up IDNA mapping for a Unicode scalar value which is not necessarily known to be valid.
    /// Values which are not valid Unicode scalars, which is to say surrogates and values above
    /// `0x10FFFF`, resolve to the `ignored` mapping without any branching.
    /// - Parameter uncheckedScalar: The unchecked Unicode scalar value to look up
    /// - Returns: The corresponding `IDNAMapping` value
    @inlinable
    package static func `for`(uncheckedScalar: UInt32) -> IDNAMapping {
        let isSurrogate = (uncheckedScalar &- 0xD800) &>> 11 == 0
        let isAboveMaxScalarValue = uncheckedScalar > 0x10_FFFF
        let isInvalid = isSurrogate || isAboveMaxScalarValue
        /// if isInvalid, replace with the first "ignored" scalar, which is `0xAD`.
        let scalar = isInvalid ? 0xAD : uncheckedScalar
        let packedValue = cswift_idna_packed_value(scalar)
        return IDNAMapping(packedValue: packedValue)
    }
}
