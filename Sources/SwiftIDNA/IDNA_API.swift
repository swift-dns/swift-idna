/// Mark: - String + IDNA

@available(SwiftStdlib 5.1, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    public func toASCII(domainName: String) throws(CollectedMappingErrors) -> String {
        try domainName.withSpan_Compatibility {
            span throws(CollectedMappingErrors) -> String in
            try self._toASCII(span: span).collect() ?? domainName
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(domainName: String) throws(CollectedMappingErrors) -> String {
        try domainName.withSpan_Compatibility {
            span throws(CollectedMappingErrors) -> String in
            try self._toUnicode(span: span).collect() ?? domainName
        }
    }
}

/// Mark: - Span + IDNA

@available(SwiftStdlib 5.1, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    ///
    /// There is no assumption on the validity of the span.
    /// It can contain UTF16 surrogate bytes which are considered invalid.
    public func toASCII(span: Span<UInt8>) throws(CollectedMappingErrors) -> ConversionResult {
        try self._toASCII(span: span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// There is no assumption on the validity of the span.
    /// It can contain UTF16 surrogate bytes which are considered invalid.
    public func toUnicode(span: Span<UInt8>) throws(CollectedMappingErrors) -> ConversionResult {
        try self._toUnicode(span: span)
    }
}

/// Mark: - UTF8Span + IDNA

@available(SwiftStdlib 6.2, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    public func toASCII(
        domainName utf8Span: UTF8Span
    ) throws(CollectedMappingErrors) -> ConversionResult {
        try self._toASCII(span: utf8Span.span)
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(
        domainName utf8Span: UTF8Span
    ) throws(CollectedMappingErrors) -> ConversionResult {
        try self._toUnicode(span: utf8Span.span)
    }
}
