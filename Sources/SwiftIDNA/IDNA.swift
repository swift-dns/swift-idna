/// Provides compatibility with IDNA: Internationalized Domain Names in Applications.
/// [Unicode IDNA Compatibility Processing](https://www.unicode.org/reports/tr46/)
@available(swiftIDNAApplePlatforms 13, *)
public struct IDNA: Sendable {
    /// [Unicode IDNA Compatibility Processing: Processing](https://www.unicode.org/reports/tr46/#Processing)
    /// All parameters are used in both `toASCII` and `toUnicode`, except for
    /// `verifyDNSLength` which is only used in `toASCII`.
    public struct Configuration: Sendable {
        /// Disallows usage of "-" (U+002D HYPHEN-MINUS) in certain positions of a domain name.
        /// [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        public var checkHyphens: Bool
        /// Checks if a domain name is valid if/when containing any bidirectional unicode characters.
        /// [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        /// `checkBidi` is currently a no-op.
        package var checkBidi: Bool = true
        /// Checks if a domain name is valid if/when containing any joiner unicode characters.
        /// [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        /// `checkJoiners` is currently a no-op.
        package var checkJoiners: Bool = true
        /// [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        public var useSTD3ASCIIRules: Bool
        /// Verifies domain name length compatibility with DNS specification.
        /// That is, each label length must be in range 1...63 and each full domain name length must
        /// be in range 1...255.
        /// [Unicode IDNA Compatibility Processing: ToASCII](https://www.unicode.org/reports/tr46/#ToASCII)
        public var verifyDNSLength: Bool
        /// Ignores invalid punycode in `toUnicode`/`mainProcessing` conversions and more, and
        /// doesn't report errors for them.
        public var ignoreInvalidPunycode: Bool
        /// Implementations may make further modifications to the resulting Unicode string when showing it to the user. For example, it is recommended that disallowed characters be replaced by a U+FFFD to make them visible to the user. Similarly, labels that fail processing during step 4 may be marked by the insertion of a U+FFFD or other visual device.
        /// Not a necessary parameter of the IDNA handling according to the Unicode document.
        /// `replaceBadCharacters` is currently a no-op.
        package var replaceBadCharacters: Bool

        /// The most strict configuration possible.
        public static var mostStrict: Configuration {
            Configuration(
                checkHyphens: true,
                checkBidi: true,
                checkJoiners: true,
                useSTD3ASCIIRules: true,
                verifyDNSLength: true,
                ignoreInvalidPunycode: false,
                replaceBadCharacters: false
            )
        }

        /// The most lax configuration possible.
        public static var mostLax: Configuration {
            Configuration(
                checkHyphens: false,
                checkBidi: false,
                checkJoiners: false,
                useSTD3ASCIIRules: false,
                verifyDNSLength: false,
                ignoreInvalidPunycode: true,
                replaceBadCharacters: false
            )
        }

        /// The default configuration.
        public static var `default`: Configuration {
            Configuration(
                checkHyphens: true,
                checkBidi: true,
                checkJoiners: true,
                useSTD3ASCIIRules: false,
                verifyDNSLength: true,
                ignoreInvalidPunycode: false,
                replaceBadCharacters: false
            )
        }

        package init(
            checkHyphens: Bool,
            checkBidi: Bool,
            checkJoiners: Bool,
            useSTD3ASCIIRules: Bool,
            verifyDNSLength: Bool,
            ignoreInvalidPunycode: Bool,
            replaceBadCharacters: Bool
        ) {
            self.checkHyphens = checkHyphens
            self.checkBidi = checkBidi
            self.checkJoiners = checkJoiners
            self.useSTD3ASCIIRules = useSTD3ASCIIRules
            self.verifyDNSLength = verifyDNSLength
            self.ignoreInvalidPunycode = ignoreInvalidPunycode
            self.replaceBadCharacters = replaceBadCharacters
        }

        /// - Parameters:
        ///   - checkHyphens: Disallows usage of "-" (U+002D HYPHEN-MINUS) in certain positions of a domain name.
        ///     [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        ///   - useSTD3ASCIIRules: [Unicode IDNA Compatibility Processing: Validity Criteria](https://www.unicode.org/reports/tr46/#Validity_Criteria)
        ///   - verifyDNSLength: Verifies domain name length compatibility with DNS specification.
        ///     That is, each label length must be in range 1...63 and each full domain name length must
        ///     be in range 1...255.
        ///     [Unicode IDNA Compatibility Processing: ToASCII](https://www.unicode.org/reports/tr46/#ToASCII)
        ///   - ignoreInvalidPunycode: Ignores invalid punycode in `toUnicode`/`mainProcessing` conversions and more,
        ///     and doesn't report errors for them.
        public init(
            checkHyphens: Bool,
            useSTD3ASCIIRules: Bool,
            verifyDNSLength: Bool,
            ignoreInvalidPunycode: Bool
        ) {
            self.checkHyphens = checkHyphens
            /// `checkBidi` is currently a no-op.
            self.checkBidi = false
            /// `checkJoiners` is currently a no-op.
            self.checkJoiners = false
            self.useSTD3ASCIIRules = useSTD3ASCIIRules
            self.verifyDNSLength = verifyDNSLength
            self.ignoreInvalidPunycode = ignoreInvalidPunycode
            /// `replaceBadCharacters` is currently a no-op.
            self.replaceBadCharacters = false
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    public func toASCII(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self.toASCII(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self.toASCII(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
    }

    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    /// This function can modify the string in-place.
    /// If you don't need the original domain name string, use this function to avoid copies.
    public func toASCII(domainName: inout String) throws(MappingErrors) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            try self.toASCII(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: true
            ).collect(into: &domainName)
            return
        }
        var copy = domainName
        try copy.withSpan_Compatibility_macOSUnder26 { span throws(MappingErrors) -> Void in
            try self.toASCII(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(into: &domainName)
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    public func toUnicode(domainName: String) throws(MappingErrors) -> String {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try self.toUnicode(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
        var copy = domainName
        return try copy.withSpan_Compatibility_macOSUnder26 {
            span throws(MappingErrors) -> String in
            try self.toUnicode(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(original: domainName)
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    /// This function can modify the string in-place.
    /// If you don't need the original domain name string, use this function to avoid copies.
    public func toUnicode(domainName: inout String) throws(MappingErrors) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            try self.toUnicode(
                uncheckedUTF8Span: domainName.utf8Span.span,
                canInPlaceModifySpanBytes: true
            ).collect(into: &domainName)
            return
        }
        var copy = domainName
        try copy.withSpan_Compatibility_macOSUnder26 { span throws(MappingErrors) -> Void in
            try self.toUnicode(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: false
            ).collect(into: &domainName)
        }
    }
}
