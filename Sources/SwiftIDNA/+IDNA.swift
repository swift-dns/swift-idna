extension IDNA {
    /// The result of checking characters for IDNA compliance.
    public enum CharacterCheckResult {
        /// The sequence contains only characters that IDNA's toASCII function won't change.
        case containsOnlyIDNANoOpCharacters
        /// The sequence contains uppercased ASCII letters that will be lowercased after IDNA's toASCII conversion.
        /// The sequence does not contain any other characters that IDNA's toASCII function will change.
        case onlyNeedsLowercasingOfUppercasedASCIILetters
        /// The sequence contains characters that IDNA's toASCII function might or might not change.
        case mightChangeAfterIDNAConversion
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// This is useful to avoid performing a toASCII IDNA conversion if it's not necessary.
    ///
    /// No negative values are allowed.
    @inlinable
    public static func performCharacterCheck(
        bytes: some Sequence<some BinaryInteger>
    ) -> CharacterCheckResult {
        /// Assert all values are non-negative.
        assert(bytes.allSatisfy { $0.signum() != -1 })

        var containsUppercased = false

        for byte in bytes {
            /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
            /// Uppercased letters are each 'mapped' to their lowercased equivalent.
            if byte.isUppercasedASCIILetter {
                containsUppercased = true
            } else if byte.isASCII {
                continue
            } else {
                return .mightChangeAfterIDNAConversion
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// Assumes the bytes are in the DNS wire format as specified in RFC 1035.
    /// This is useful to avoid performing a toASCII IDNA conversion if it's not necessary.
    @inlinable
    public static func performCharacterCheck(
        dnsWireFormatBytes bytes: some Sequence<UInt8>
    ) -> CharacterCheckResult {
        var containsUppercased = false
        var iterator = bytes.makeIterator()

        whileLoop: while let length = iterator.next() {
            for _ in 0..<length {
                guard let byte = iterator.next() else {
                    break whileLoop
                }
                /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
                /// Uppercased letters are each 'mapped' to their lowercased equivalent.
                if byte.isUppercasedASCIILetter {
                    containsUppercased = true
                } else if byte.isASCII {
                    continue
                } else {
                    return .mightChangeAfterIDNAConversion
                }
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a toASCII IDNA conversion if it's not necessary.
    @inlinable
    public static func performCharacterCheck(
        string: some StringProtocol
    ) -> CharacterCheckResult {
        var containsUppercased = false

        for scalar in string.unicodeScalars {
            /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
            /// Uppercased letters are each 'mapped' to their lowercased equivalent.
            if scalar.isUppercasedASCIILetter {
                containsUppercased = true
            } else if scalar.isASCII {
                continue
            } else {
                return .mightChangeAfterIDNAConversion
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a toASCII IDNA conversion if it's not necessary.
    @available(swiftIDNAApplePlatforms 13, *)
    @inlinable
    public static func performCharacterCheck(
        span: Span<UInt8>
    ) -> CharacterCheckResult {
        var containsUppercased = false

        for idx in span.indices {
            let byte = span[unchecked: idx]
            /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
            /// Uppercased letters are each 'mapped' to their lowercased equivalent.
            if byte.isUppercasedASCIILetter {
                containsUppercased = true
            } else if byte.isASCII {
                continue
            } else {
                return .mightChangeAfterIDNAConversion
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }
}
