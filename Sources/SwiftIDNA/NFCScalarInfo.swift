public import CSwiftIDNA

@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct NFCScalarInfo {
    /// [UAX #15: Detecting Normalization Forms](https://www.unicode.org/reports/tr15/#Detecting_Normalization_Forms)
    @usableFromInline
    package enum Tag: UInt16 {
        /// Canonical Combining Class 0, no canonical decomposition.
        /// Translates to `Yes` in NFC Quick Check algorithm (`NFC_QC`).
        /// Unaffected by normalization.
        case inert = 0
        /// Nonzero Canonical Combining Class and no canonical decomposition.
        /// Translates to `Yes` in NFC Quick Check algorithm (`NFC_QC`).
        /// Decomposition process inserts it in canonical order by its Canonical Combining Class.
        /// [The Unicode Standard, 3.11.5 Canonical Ordering Algorithm](https://www.unicode.org/versions/Unicode18.0.0/UnicodeStandard-18.0.pdf)
        case cccOnly = 1
        /// No canonical decomposition.
        /// Translates to `Maybe` in NFC Quick Check algorithm (`NFC_QC`).
        /// Canonically ordered like `cccOnly`, then Composition process may fold it into the preceding starter.
        /// [The Unicode Standard, 3.11.4 Starters](https://www.unicode.org/versions/Unicode18.0.0/UnicodeStandard-18.0.pdf)
        case maybe = 2
        /// With a canonical decomposition to expand before recomposing.
        /// Translates to `Maybe` in NFC Quick Check algorithm (`NFC_QC`).
        case maybeWithDecomposition = 3
        /// With a canonical decomposition that recomposes back into this scalar.
        /// Translates to `Yes` in NFC Quick Check algorithm (`NFC_QC`).
        case decompositionQCYes = 4
        /// With a canonical decomposition.
        /// Translates to `No` in NFC Quick Check algorithm (`NFC_QC`).
        /// The scalar never appears in NFC output.
        case decompositionQCNo = 5
        /// A pre-composed Hangul syllable in `U+AC00...U+D7A3`.
        /// Translates to `Yes` in NFC Quick Check algorithm (`NFC_QC`).
        /// Carries no decomposition data: Decomposition process derives the L/V/T Jamo
        /// arithmetically, and Composition process recomposes them without consulting the pair table.
        /// [The Unicode Standard, 3.12 Conjoining Jamo Behavior](https://www.unicode.org/versions/Unicode18.0.0/UnicodeStandard-18.0.pdf)
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
