@available(swiftIDNAApplePlatforms 10.15, *)
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
    ///
    /// Note that based on the DNS wire format only a-z, A-Z, 0-9 and `-` are allowed.
    /// So for example `_` is not allowed.
    /// In IDNA however, `_` (and the other ASCII characters) are considered valid.
    /// IDNA will simply keep those characters as is.
    /// If you want to be complaint with the DNS wire format, you need to ensure those unacceptable
    /// ASCII characters are not present in the sequence. This is out of scope for this library.
    @inlinable
    public static func performByteCheck(
        onDNSWireFormatSpan span: Span<UInt8>
    ) -> CharacterCheckResult? {
        var containsUppercased = false

        var idx = 0
        while idx < span.count {
            let length = Int(span[unchecked: idx])

            guard span.count > idx &+ length else {
                return nil
            }

            for anotherIdx in 0..<length {
                /// We checked above that the span has enough elements, so we can safely index it.
                let byte = span[unchecked: idx &+ anotherIdx &+ 1]

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

            idx &+= length &+ 1
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
    @inlinable
    public static func performByteCheck(
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
    public static func performByteCheck(
        on substring: Substring
    ) -> CharacterCheckResult {
        var substring = substring
        return substring.withSpan_Compatibility {
            performByteCheck(on: $0)
        }
    }
}
