/// Mark: - String + IDNA

@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    public func toASCII(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self._toASCII(
                _uncheckedAssumingValidUTF8: domainName.utf8Span.span
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self._toASCII(
                _uncheckedAssumingValidUTF8: span
            ).collect(original: domainName)
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self._toUnicode(
                _uncheckedAssumingValidUTF8: domainName.utf8Span.span
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self._toUnicode(
                _uncheckedAssumingValidUTF8: span
            ).collect(original: domainName)
        }
    }
}

/// Mark: - Span + IDNA

@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    ///
    /// The `span` will be assumed to be coming right from a `String`'s bytes.
    /// For example from `String.utf8Span.span`.
    /// Violating this assumption can result in undefined behavior.
    public func toASCII(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// The `span` will be assumed to be coming right from a `String`'s bytes.
    /// For example from `String.utf8Span.span`.
    /// Violating this assumption can result in undefined behavior.
    public func toUnicode(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: span)
    }
}

/// Mark: - UTF8Span + IDNA

@available(swiftIDNAApplePlatforms 26, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    public func toASCII(
        domainNameUTF8Span utf8Span: UTF8Span
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: utf8Span.span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(
        domainNameUTF8Span utf8Span: UTF8Span
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: utf8Span.span)
    }
}
