@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNA {
    /// The result of checking characters for IDNA compliance.
    @usableFromInline
    enum CharacterCheckResult {
        /// The sequence contains only characters that IDNA's toASCII function won't change.
        case containsOnlyIDNANoOpCharacters
        /// The sequence contains uppercased ASCII letters that will be lowercased after IDNA's toASCII conversion.
        /// The sequence does not contain any other characters that IDNA's toASCII function will change.
        case onlyNeedsLowercasingOfUppercasedASCIILetters
        /// The sequence contains characters that IDNA's toASCII function might or might not change.
        case mightChangeAfterIDNAConversion
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    ///
    /// No negative values are allowed.
    @inlinable
    static func performByteCheck(on span: Span<UInt8>) -> CharacterCheckResult {
        /// The compiler will use SIMD instructions to perform the bitwise operations below,
        /// which will speed up the process.
        var isASCII_Number: UInt8 = 0
        var forSureContainsLowercasedOnly_Number: UInt8 = 0
        for idx in span.indices {
            let byte = span[unchecked: idx]
            isASCII_Number |= byte
            forSureContainsLowercasedOnly_Number &= byte
        }
        let isASCII = isASCII_Number <= 0x7F

        guard isASCII else {
            return .mightChangeAfterIDNAConversion
        }

        /// If the sixth bit is set then this for sure doesn't contain an uppercased letter because
        /// those all have the sixth bit turned off.
        /// a-z and 0-9 have the sixth bit turned on, so if a string only consists of a-b and 0-9, which
        /// should be most of the cases, then this check will skip the rest of the work below.
        let forSureContainsLowercasedOnly =
            forSureContainsLowercasedOnly_Number & 0b100000 == 0b100000

        if forSureContainsLowercasedOnly {
            return .containsOnlyIDNANoOpCharacters
        }

        for idx in span.indices {
            let byte = span[unchecked: idx]
            /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
            /// Uppercased letters are each 'mapped' to their lowercased equivalent.
            if byte.isUppercasedASCIILetter {
                return .onlyNeedsLowercasingOfUppercasedASCIILetters
            }
        }

        return .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    @inlinable
    static func performByteCheck(
        on string: String
    ) -> CharacterCheckResult {
        var string = string
        return string.withSpan_Compatibility {
            performByteCheck(on: $0)
        }
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    @inlinable
    static func performByteCheck(
        on substring: Substring
    ) -> CharacterCheckResult {
        var substring = substring
        return substring.withSpan_Compatibility {
            performByteCheck(on: $0)
        }
    }
}
