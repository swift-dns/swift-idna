public import BasicContainers

@available(SwiftStdlib 5.1, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @inlinable
    func _toASCII(
        convertedBytes: inout TemporaryArray<UInt8>,
        processedBytes: inout TemporaryArray<UInt8>,
        errors: inout MappingErrors
    ) -> ConversionResult {
        assert(convertedBytes.span.checkUTF8())
        assert(processedBytes.span.checkUTF8())
        /// From now on we know we are operating only on valid UTF-8 bytes.

        // 2., 3.
        let outputReuseCapacityHint = convertedBytes.count
        convertedBytes.removeAllKeepingCapacity()

        return withIDNATemporaryBuffer(preferredCapacity: outputReuseCapacityHint) {
            (outputBufferForReuse) -> ConversionResult in

            let processedBytesSpan = processedBytes.span
            var baseDecodedUnicodeScalars = DecodedUnicodeScalars(
                utf8Bytes: processedBytesSpan,
                errors: &errors
            )
            var decodedUnicodeScalars = DecodedUnicodeScalars.Subsequence(
                base: &baseDecodedUnicodeScalars
            )

            var startIndex = 0

            for idx in processedBytesSpan.indices {
                /// If this is not a label separator, then continue
                var endIndex = idx
                let countBehindX = idx
                switch countBehindX {
                case 0, 1, 2:
                    guard processedBytesSpan[idx] == .asciiDot else {
                        continue
                    }
                case 3...:
                    let third = processedBytesSpan[idx]
                    let second = unsafe processedBytesSpan[unchecked: idx &- 1]
                    let first = unsafe processedBytesSpan[unchecked: idx &- 2]
                    if !Span<UInt8>.isIDNALabelSeparator(first, second, third),
                        third != .asciiDot
                    {
                        continue
                    }
                    if third != .asciiDot {
                        /// Set last index to bytes before e.g. `U+3002 ( 。 ) IDEOGRAPHIC FULL STOP`
                        /// which is 3 bytes, not 1, like `U+002E ( . ) FULL STOP` (asciiDot) is.
                        endIndex = idx &- 2
                    }
                default:
                    fatalError("Invalid count behind X: \(countBehindX)")
                }

                appendLabel(
                    domainNameSpan: processedBytesSpan,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    appendDot: true,
                    convertedBytes: &convertedBytes,
                    outputBufferForReuse: &outputBufferForReuse,
                    decodedUnicodeScalars: &decodedUnicodeScalars,
                    errors: &errors
                )

                startIndex = idx &+ 1
            }

            /// Last label
            appendLabel(
                domainNameSpan: processedBytesSpan,
                startIndex: startIndex,
                endIndex: processedBytesSpan.count,
                appendDot: false,
                convertedBytes: &convertedBytes,
                outputBufferForReuse: &outputBufferForReuse,
                decodedUnicodeScalars: &decodedUnicodeScalars,
                errors: &errors
            )

            if configuration.verifyDNSLength {
                if convertedBytes.count >= 254 {
                    errors.append(
                        .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
                            length: convertedBytes.count,
                            labels: [UInt8](copying: convertedBytes.span)
                        )
                    )
                }
                if convertedBytes.isEmpty {
                    /// FIXME: this line is never triggered in tests. Why?
                    /// It doesn't affect the conversion result at all, but I should still investigate.
                    errors.append(
                        .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(
                            labels: [UInt8](copying: convertedBytes.span)
                        )
                    )
                }
            }

            return convertedBytes.takeAsConversionResult()
        }
    }

    @inlinable
    func appendLabel(
        domainNameSpan bytesSpan: Span<UInt8>,
        startIndex: Int,
        endIndex: Int,
        appendDot: Bool,
        convertedBytes: inout TemporaryArray<UInt8>,
        outputBufferForReuse: inout TemporaryArray<UInt8>,
        decodedUnicodeScalars: inout DecodedUnicodeScalars.Subsequence,
        errors: inout MappingErrors
    ) {
        let range = unsafe Range<Int>(uncheckedBounds: (startIndex, endIndex))
        let labelSpan = unsafe bytesSpan.extracting(unchecked: range)
        var labelByteLength = 0
        if labelSpan.isASCII {
            labelByteLength = labelSpan.count
            convertedBytes.append(
                addingCount: labelSpan.count &+ 1
            ) { output in
                output.swift_idna_append(copying: labelSpan)
                if appendDot {
                    output.append(.asciiDot)
                }
            }
        } else {
            decodedUnicodeScalars.set(utf8OffsetRange: range)

            Punycode.encode(
                inputBytesSpan: labelSpan,
                outputBufferForReuse: &outputBufferForReuse,
                decodedUnicodeScalars: decodedUnicodeScalars
            )

            labelByteLength = 4 &+ outputBufferForReuse.count
            convertedBytes.append(
                addingCount: 4 &+ outputBufferForReuse.count &+ 1
            ) { output in
                output.append(.asciiLowercasedX)
                output.append(.asciiLowercasedN)
                output.append(.asciiHyphenMinus)
                output.append(.asciiHyphenMinus)
                output.swift_idna_append(copying: outputBufferForReuse.span)
                if appendDot {
                    output.append(.asciiDot)
                }
            }
        }

        if configuration.verifyDNSLength {
            if labelByteLength > 63 {
                errors.append(
                    .trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(
                        length: labelByteLength,
                        labels: [UInt8](copying: convertedBytes.span)
                    )
                )
            }

            if labelByteLength == 0 {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(
                        labels: [UInt8](copying: convertedBytes.span)
                    )
                )
            }
        }
    }

    /// Main `Processing` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#Processing
    ///
    /// Excluding step 1 (Map).
    @inlinable
    @inline(__always)
    func _mainProcessing(
        reuseBuffer newBytes: inout TemporaryArray<UInt8>,
        output newerBytes: inout TemporaryArray<UInt8>,
        errors: inout MappingErrors
    ) {
        assert(newBytes.span.checkUTF8())
        assert(newerBytes.isEmpty)
        /// From now on we know we are operating only on valid UTF-8 bytes.

        /// 2. Normalize

        /// Make `newBytes` NFC, if not already NFC
        newBytes._uncheckedAssumingValidUTF8_ensureNFC()
        newerBytes.reserveCapacity(newBytes.count)

        let newBytesSpan = newBytes.span
        var scalarsForReuse = LinkedList<UnicodeScalarValue>()

        var startIndex = 0
        for idx in newBytesSpan.indices {
            /// Unchecked because idx comes right from `newBytesSpan.indices`
            guard newBytesSpan[idx] == .asciiDot else {
                continue
            }

            let range = unsafe Range<Int>(uncheckedBounds: (startIndex, idx))
            let chunk = unsafe newBytesSpan.extracting(unchecked: range)

            if convertAndValidateLabel(
                chunk,
                scalarsForReuse: &scalarsForReuse,
                newerBytes: &newerBytes,
                errors: &errors
            ) {
                newerBytes.append(.asciiDot)
            }

            startIndex = idx &+ 1
        }

        let range = unsafe Range<Int>(uncheckedBounds: (startIndex, newBytesSpan.count))
        let chunk = unsafe newBytesSpan.extracting(unchecked: range)
        _ = convertAndValidateLabel(
            chunk,
            scalarsForReuse: &scalarsForReuse,
            newerBytes: &newerBytes,
            errors: &errors
        )
    }

    /// https://www.unicode.org/reports/tr46/#ProcessingStepConvertValidate
    /// Returns true if succeeded.
    @inlinable
    func convertAndValidateLabel(
        _ span: Span<UInt8>,
        scalarsForReuse: inout LinkedList<UnicodeScalarValue>,
        newerBytes: inout TemporaryArray<UInt8>,
        errors: inout MappingErrors
    ) -> Bool {
        /// Checks if the label starts with “xn--”
        guard span.hasIDNADomainNameMarkerPrefix else {
            verifyValidLabel(_uncheckedAssumingValidUTF8: span, errors: &errors)
            newerBytes.append(copying: span)
            return true
        }

        /// 4.1:
        if !configuration.ignoreInvalidPunycode,
            !span.isASCII
        {
            errors.append(
                .labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(
                    label: String(span: span)
                )
            )
            /// continue to next label
            return false
        }

        /// 4.2:
        /// If conversion fails, and we're not ignoring invalid punycode, record an error

        /// Drop the "xn--" prefix
        let noXNRange = unsafe Range<Int>(uncheckedBounds: (4, span.count))
        let currentNewerBytesCount = newerBytes.count

        if Punycode.decode(
            _uncheckedAssumingValidUTF8: unsafe span.extracting(unchecked: noXNRange),
            scalarsForReuse: &scalarsForReuse,
            outputBuffer: &newerBytes
        ) {
            let range = unsafe Range<Int>(
                uncheckedBounds: (currentNewerBytesCount, newerBytes.count)
            )

            let newerBytesSpan = newerBytes.span
            let conversionSpan = unsafe newerBytesSpan.extracting(unchecked: range)

            /// 4.3:
            checkInvalidPunycode(span: conversionSpan, errors: &errors)

            verifyValidLabel(_uncheckedAssumingValidUTF8: conversionSpan, errors: &errors)

            return true
        } else {
            switch configuration.ignoreInvalidPunycode {
            case true:
                /// Use the original label

                /// 4.3:
                checkInvalidPunycode(span: span, errors: &errors)

                verifyValidLabel(_uncheckedAssumingValidUTF8: span, errors: &errors)

                newerBytes.append(copying: span)
                return true
            case false:
                errors.append(
                    .labelPunycodeDecodeFailed(
                        label: String(span: span)
                    )
                )
                /// continue to next label
                return false
            }
        }
    }

    @inlinable
    func checkInvalidPunycode(span: Span<UInt8>, errors: inout MappingErrors) {
        if configuration.ignoreInvalidPunycode {
            return
        }

        if span.isEmpty {
            errors.append(
                .labelIsEmptyAfterPunycodeConversion(
                    label: String(span: span)
                )
            )
        }

        if span.isASCII {
            errors.append(
                .labelContainsOnlyASCIIAfterPunycodeDecode(
                    label: String(span: span)
                )
            )
        }
    }

    /// https://www.unicode.org/reports/tr46/#Validity_Criteria
    @inlinable
    func verifyValidLabel(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>,
        errors: inout MappingErrors
    ) {
        if !configuration.ignoreInvalidPunycode,
            !NFCNormalization.isInNFC(span)
        {
            errors.append(
                .labelIsNotInNormalizationFormC(
                    label: String(span: span)
                )
            )
        }

        switch configuration.checkHyphens {
        case true:
            let bytesCount = span.count
            if bytesCount >= 4,
                span[2] == UInt8.asciiHyphenMinus,
                span[3] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(
                        label: String(span: span)
                    )
                )
            }
            if bytesCount >= 1,
                span[0] == UInt8.asciiHyphenMinus
                    || span[bytesCount - 1] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(
                        label: String(span: span)
                    )
                )
            }
        case false:
            if !configuration.ignoreInvalidPunycode,
                span.hasIDNADomainNameMarkerPrefix
            {
                errors.append(
                    .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                        label: String(span: span)
                    )
                )
            }
        }

        var unicodeScalarsIterator = UnicodeScalarIterator()
        if !configuration.ignoreInvalidPunycode,
            let firstUncheckedScalar = unicodeScalarsIterator.next(in: span),
            let firstScalar = UnicodeScalarValue(firstUncheckedScalar),
            firstScalar.isMark
        {
            errors.append(
                .labelStartsWithCombiningMark(
                    label: String(span: span)
                )
            )
        }

        if !configuration.ignoreInvalidPunycode || configuration.useSTD3ASCIIRules {
            var unicodeScalarsIterator = UnicodeScalarIterator()

            while let uncheckedScalar = unicodeScalarsIterator.next(in: span) {
                guard let scalar = UnicodeScalarValue(uncheckedScalar) else {
                    /// Error already appended in mapToIDNAMappings
                    continue
                }

                if !configuration.ignoreInvalidPunycode {
                    let mapping = IDNAMapping.for(scalar: scalar)
                    switch mapping.tag {
                    case .validNone, .validNV8, .validXV8, .deviation:
                        break
                    case .mapped, .disallowed, .ignored:
                        errors.append(
                            .labelContainsInvalidUnicode(
                                uncheckedScalar,
                                label: String(span: span)
                            )
                        )
                    }
                }

                if configuration.useSTD3ASCIIRules {
                    if scalar.isASCII,
                        !scalar.value.isLowercasedLetterOrDigitOrHyphenMinus
                    {
                        errors.append(
                            .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                                label: String(span: span)
                            )
                        )
                    }
                }
            }
        }

        // if configuration.checkJoiners {
        // TODO: implement
        // }

        // if configuration.checkBidi {
        // TODO: implement
        // }
    }
}
