/// Mark: - String + IDNA

@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    public func toASCII(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self._toASCII(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self._toASCII(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
    }

    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    ///
    /// This function can modify the string in-place.
    /// If you don't need the original domain name string, use this function to avoid copies.
    public func toASCII(domainName: inout String) throws(MappingErrors) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            try self._toASCII(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: true
            ).collect(into: &domainName)
            return
        }
        var copy = domainName
        try copy.withSpan_Compatibility_macOSUnder26 { span throws(MappingErrors) -> Void in
            try self._toASCII(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(into: &domainName)
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self._toUnicode(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self._toUnicode(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// This function can modify the string in-place.
    /// If you don't need the original domain name string, use this function to avoid copies.
    public func toUnicode(domainName: inout String) throws(MappingErrors) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            try self._toUnicode(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: true
            ).collect(into: &domainName)
            return
        }
        var copy = domainName
        try copy.withSpan_Compatibility_macOSUnder26 { span throws(MappingErrors) -> Void in
            try self._toUnicode(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(into: &domainName)
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
        uncheckedDomainNameBytesSpan span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(
            uncheckedUTF8Span: span,
            canInPlaceModifySpanBytes: false
        )
    }

    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#toASCII
    ///
    /// The `span` will be assumed to be coming right from a `String`'s bytes.
    /// For example from `String.utf8Span.span`.
    /// Violating this assumption can result in undefined behavior.
    ///
    /// If `canInPlaceModifySpanBytes` is `true`, the implementation will assume ownership
    /// of this span and might in-place modify the underlying bytes to be more efficient.
    /// **Note that the original collection (e.g. `String`) that this span came from might also be modified.**
    public func toASCII(
        uncheckedDomainNameBytesSpan span: Span<UInt8>,
        canInPlaceModifySpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        try self._toASCII(
            uncheckedUTF8Span: span,
            canInPlaceModifySpanBytes: canInPlaceModifySpanBytes
        )
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// The `span` will be assumed to be coming right from a `String`'s bytes.
    /// For example from `String.utf8Span.span`.
    /// Violating this assumption can result in undefined behavior.
    public func toUnicode(
        uncheckedDomainNameBytesSpan span: Span<UInt8>
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(
            uncheckedUTF8Span: span,
            canInPlaceModifySpanBytes: false
        )
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    ///
    /// The `span` will be assumed to be coming right from a `String`'s bytes.
    /// For example from `String.utf8Span.span`.
    /// Violating this assumption can result in undefined behavior.
    ///
    /// If `canInPlaceModifySpanBytes` is `true`, the implementation will assume ownership
    /// of this span and might in-place modify the underlying bytes to be more efficient.
    /// **Note that the original collection (e.g. `String`) that this span came from might also be modified.**
    public func toUnicode(
        uncheckedDomainNameBytesSpan span: Span<UInt8>,
        canInPlaceModifySpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(
            uncheckedUTF8Span: span,
            canInPlaceModifySpanBytes: canInPlaceModifySpanBytes
        )
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
        try self._toUnicode(
            uncheckedUTF8Span: utf8Span.span,
            canInPlaceModifySpanBytes: false
        )
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(
        domainNameUTF8Span utf8Span: UTF8Span
    ) throws(MappingErrors) -> ConversionResult {
        try self._toUnicode(
            uncheckedUTF8Span: utf8Span.span,
            canInPlaceModifySpanBytes: false
        )
    }
}
