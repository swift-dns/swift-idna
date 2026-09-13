public import CSwiftIDNA

@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct NFCScalarInfo {
    @usableFromInline
    package enum Tag: UInt16 {
        case inert = 0
        case cccOnly = 1
        case maybe = 2
        case maybeWithDecomposition = 3
        case decompositionQCYes = 4
        case decompositionQCNo = 5
        case hangulSyllable = 6
    }

    @usableFromInline
    package let tag: Tag
    /// The scalar's canonical combining class for the `cccOnly` and `maybe` tags, or an index
    /// into the decomposition slices for the decomposing tags. Otherwise always 0.
    @usableFromInline
    package let payload: UInt16

    @inlinable
    init(tag: Tag, payload: UInt16) {
        self.tag = tag
        self.payload = payload
    }

    /// Look up NFC normalization info for a given Unicode scalar.
    /// - Parameter scalar: The Unicode scalar value to look up
    /// - Returns: The corresponding `NFCScalarInfo` value
    @inlinable
    package static func `for`(scalar: UInt32) -> NFCScalarInfo {
        let packedValue = cswift_idna_nfc_value(scalar)
        /// This is exhaustively tested, so `unsafelyUnwrapped` is safe.
        let tag = unsafe Tag(rawValue: packedValue >> 13).unsafelyUnwrapped
        return NFCScalarInfo(tag: tag, payload: packedValue & 0x1FFF)
    }
}
