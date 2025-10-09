@available(swiftIDNAApplePlatforms 13, *)
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
    /// Assumes the bytes are in the DNS wire format as specified in RFC 1035.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    @inlinable
    public static func performDNSComplaintByteCheck(
        onDNSWireFormatSpan span: Span<UInt8>
    ) -> CharacterCheckResult? {
        var containsUppercased = false

        for idx in span.indices {
            let length = span[unchecked: idx]

            guard span.count > idx &+ Int(length) else {
                return nil
            }

            for anotherIdx in 1...length {
                /// We checked above that the span has enough elements, so we can safely index it.
                let byte = span[unchecked: idx &+ Int(anotherIdx)]

                /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
                /// Uppercased letters are each 'mapped' to their lowercased equivalent.
                ///
                /// Based on DNS wire format though, only latin letters, digits, and hyphens are allowed.
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

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    ///
    /// No negative values are allowed.
    @inlinable
    public static func performByteCheck(
        on span: Span<some BinaryInteger>
    ) -> CharacterCheckResult {
        /// Assert all values are non-negative.
        assert(span.allSatisfy { $0.signum() != -1 })

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

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    public static func performByteCheck(
        on string: String
    ) -> CharacterCheckResult {
        var string = string
        return string.withSpan_Compatibility_macOSUnder26 {
            performByteCheck(on: $0)
        }
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    public static func performByteCheck(
        on substring: Substring
    ) -> CharacterCheckResult {
        var substring = substring
        return substring.withSpan_Compatibility_macOSUnder26 {
            performByteCheck(on: $0)
        }
    }
}

@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    /// The result of checking characters for IDNA compliance.
    public enum DNSFormatCharacterCheckResult {
        /// The sequence contains only characters that IDNA's toASCII function won't change.
        case containsOnlyIDNANoOpCharacters
        /// The sequence contains uppercased ASCII letters that will be lowercased after IDNA's toASCII conversion.
        /// The sequence does not contain any other characters that IDNA's toASCII function will change.
        case onlyNeedsLowercasingOfUppercasedASCIILetters
        /// The sequence contains characters that IDNA's toASCII function might or might not change.
        case mightChangeAfterIDNAConversion
        /// The sequence contains characters that are not valid for DNS domain names.
        /// This usually means there are ASCII characters other than letters, digits, and hyphens in the input.
        case containsInvalidDNSCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// Assumes the bytes are in the DNS wire format as specified in RFC 1035.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    @inlinable
    public static func performDNSComplaintByteCheck(
        onDNSWireFormatSpan span: Span<UInt8>
    ) -> DNSFormatCharacterCheckResult? {
        var containsUppercased = false

        for idx in span.indices {
            let length = span[unchecked: idx]

            guard span.count > idx &+ Int(length) else {
                return nil
            }

            for anotherIdx in 1...length {
                /// We checked above that the span has enough elements, so we can safely index it.
                let byte = span[unchecked: idx &+ Int(anotherIdx)]

                /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
                /// Uppercased letters are each 'mapped' to their lowercased equivalent.
                ///
                /// Based on DNS wire format though, only latin letters, digits, and hyphens are allowed.
                if byte.isUppercasedASCIILetter {
                    containsUppercased = true
                } else if byte.isLowercasedLetterOrDigitOrHyphenMinus {
                    continue
                } else if byte.isASCII {
                    return .containsInvalidDNSCharacters
                } else {
                    return .mightChangeAfterIDNAConversion
                }
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the sequence.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    ///
    /// No negative values are allowed.
    @inlinable
    public static func performDNSComplaintByteCheck(
        on span: Span<some BinaryInteger>
    ) -> DNSFormatCharacterCheckResult {
        /// Assert all values are non-negative.
        assert(span.allSatisfy { $0.signum() != -1 })

        var containsUppercased = false

        for idx in span.indices {
            let byte = span[unchecked: idx]
            /// Based on IDNA, all ASCII characters other than uppercased letters are 'valid'
            /// Uppercased letters are each 'mapped' to their lowercased equivalent.
            if byte.isUppercasedASCIILetter {
                containsUppercased = true
            } else if byte.isLowercasedLetterOrDigitOrHyphenMinus {
                continue
            } else if byte.isASCII {
                return .containsInvalidDNSCharacters
            } else {
                return .mightChangeAfterIDNAConversion
            }
        }

        return containsUppercased
            ? .onlyNeedsLowercasingOfUppercasedASCIILetters : .containsOnlyIDNANoOpCharacters
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    public static func performDNSComplaintByteCheck(
        on string: String
    ) -> DNSFormatCharacterCheckResult {
        var string = string
        return string.withSpan_Compatibility_macOSUnder26 {
            performDNSComplaintByteCheck(on: $0)
        }
    }

    /// Checks the bytes to foresee if an IDNA conversion will modify the string.
    /// This is useful to avoid performing a ToASCII IDNA conversion if it's not necessary.
    public static func performDNSComplaintByteCheck(
        on substring: Substring
    ) -> DNSFormatCharacterCheckResult {
        var substring = substring
        return substring.withSpan_Compatibility_macOSUnder26 {
            performDNSComplaintByteCheck(on: $0)
        }
    }
}
