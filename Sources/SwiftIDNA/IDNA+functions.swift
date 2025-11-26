/// Mark: - String + IDNA

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    public func toASCII(domainName: String) throws(MappingErrors) -> String {
        var copy = domainName
        return try copy.withSpan_Compatibility {
            span throws(MappingErrors) -> String in
            try self._toASCII(
                _uncheckedAssumingValidUTF8: span
            ).collect() ?? domainName
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(domainName: String) throws(MappingErrors) -> String {
        var copy = domainName
        return try copy.withSpan_Compatibility {
            span throws(MappingErrors) -> String in
            try self._toUnicode(
                _uncheckedAssumingValidUTF8: span
            ).collect() ?? domainName
        }
    }
}

/// Mark: - Span + IDNA

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    ///
    /// The `span` will be assumed to be valid `String` UTF8 bytes.
    /// For example `String.utf8Span.span` is a valid span.
    /// Violating this assumption can result in undefined behavior.
    public func toASCII(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toASCII(_uncheckedAssumingValidUTF8: span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// The `span` will be assumed to be valid `String` UTF8 bytes.
    /// For example `String.utf8Span.span` is a valid span.
    /// Violating this assumption can result in undefined behavior.
    public func toUnicode(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: span)
    }
}

/// Mark: - UTF8Span + IDNA

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    public func toASCII(
        domainName utf8Span: UTF8Span
    ) throws(MappingErrors) -> ConversionResult {
        try self._toASCII(_uncheckedAssumingValidUTF8: utf8Span.span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(
        domainName utf8Span: UTF8Span
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(_uncheckedAssumingValidUTF8: utf8Span.span)
    }
}
