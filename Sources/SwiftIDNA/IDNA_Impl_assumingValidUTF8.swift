@available(SwiftStdlib 5.1, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @inlinable
    func _toASCII(
        convertedBytes: inout TinyBuffer,
        processedBytes: inout TinyBuffer,
        errors: inout MappingErrors
    ) -> ConversionResult {
        assert(convertedBytes.withSpan { $0.checkUTF8() })
        assert(processedBytes.withSpan { $0.checkUTF8() })
        /// From now on we know we are operating only on valid UTF-8 bytes.

        // 2., 3.
        let outputReuseCapacityHint = convertedBytes.count
        convertedBytes.removeAll(keepingCapacity: true)

        return TinyBuffer.withInlineAllocation(preferredCapacity: outputReuseCapacityHint) {
            (outputBufferForReuse) -> ConversionResult in

            processedBytes.withSpan { processedBytesSpan in
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
                                labels: [UInt8](copying: convertedBytes)
                            )
                        )
                    }
                    if convertedBytes.isEmpty {
                        /// FIXME: this line is never triggered in tests. Why?
                        /// It doesn't affect the conversion result at all, but I should still investigate.
                        errors.append(
                            .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(
                                labels: [UInt8](copying: convertedBytes)
                            )
                        )
                    }
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
        convertedBytes: inout TinyBuffer,
        outputBufferForReuse: inout TinyBuffer,
        decodedUnicodeScalars: inout DecodedUnicodeScalars.Subsequence,
        errors: inout MappingErrors
    ) {
        let range = unsafe Range<Int>(uncheckedBounds: (startIndex, endIndex))
        let labelSpan = unsafe bytesSpan.extracting(unchecked: range)
        var labelByteLength = 0
        if labelSpan.isASCII {
            labelByteLength = labelSpan.count
            convertedBytes.append(
                extraRequiredCapacity: labelSpan.count &+ 1
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
                extraRequiredCapacity: 4 &+ outputBufferForReuse.count &+ 1
            ) { output in
                output.append(.asciiLowercasedX)
                output.append(.asciiLowercasedN)
                output.append(.asciiHyphenMinus)
                output.append(.asciiHyphenMinus)
                outputBufferForReuse.withSpan { output.swift_idna_append(copying: $0) }
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
                        labels: [UInt8](copying: convertedBytes)
                    )
                )
            }

            if labelByteLength == 0 {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(
                        labels: [UInt8](copying: convertedBytes)
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
        reuseBuffer newBytes: inout TinyBuffer,
        output newerBytes: inout TinyBuffer,
        errors: inout MappingErrors
    ) {
        assert(newBytes.withSpan { $0.checkUTF8() })
        assert(newerBytes.isEmpty)
        /// From now on we know we are operating only on valid UTF-8 bytes.

        /// 2. Normalize

        /// Make `newBytes` NFC, if not already NFC
        newBytes._uncheckedAssumingValidUTF8_ensureNFC()
        newerBytes.reserveCapacity(newBytes.count)

        newBytes.withSpan { newBytesSpan in
            let maxRequiredCapacityForAllLabels = self.maxLabelLength(span: newBytesSpan)
            var scalarsIndexToUTF8IndexForReuse = LazyRigidArray<Int>(
                capacity: maxRequiredCapacityForAllLabels
            )

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
                    scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
                    newerBytes: &newerBytes,
                    errors: &errors
                ) {
                    newerBytes.append(unchecked: .asciiDot)
                }

                startIndex = idx &+ 1
            }

            let range = unsafe Range<Int>(uncheckedBounds: (startIndex, newBytesSpan.count))
            let chunk = unsafe newBytesSpan.extracting(unchecked: range)
            _ = convertAndValidateLabel(
                chunk,
                scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
                newerBytes: &newerBytes,
                errors: &errors
            )
        }
    }

    /// Returns the length of the longest label in the given span.
    /// Assumes the span does not contain any label separators other than `.`.
    @inlinable
    func maxLabelLength(span: Span<UInt8>) -> Int {
        let count = span.count

        var maxLabelLength = 0
        var startIndex = 0

        return span.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return 0
            }

            var idx = 0
            /// Only enter the loop while a full 8-byte word still fits.
            while idx &+ 8 <= count {
                /// Load the next eight bytes as a little-endian word, so that byte `idx` is
                /// the least significant one and bit positions map back to byte offsets.
                let word = unsafe UInt64(
                    littleEndian: base.loadUnaligned(fromByteOffset: idx, as: UInt64.self)
                )
                /// Every byte that equals `.` (0x2E) becomes 0, every other byte becomes non-zero.
                let dots = word ^ 0x2E2E_2E2E_2E2E_2E2E
                /// Adding `0x7F` to the low 7 bits of each byte sets that byte's high bit whenever
                /// those 7 bits are non-zero. It cannot carry across bytes, as `0x7F &+ 0x7F` stays
                /// below `0x100`, so unlike a `&-` this never contaminates a neighboring byte.
                let low7BitsRaised = (dots & 0x7F7F_7F7F_7F7F_7F7F) &+ 0x7F7F_7F7F_7F7F_7F7F
                /// Fold the original high bit back in, so each byte's high bit is set exactly when
                /// the byte was non-zero, that is, when it was not a `.`.
                let nonZeroBytes = low7BitsRaised | dots
                /// Invert and keep just the high bits, leaving every `.` as a single `0x80` marker.
                let mask = ~nonZeroBytes & 0x8080_8080_8080_8080

                /// No `.` in these eight bytes, the common case, so extend the current label by
                /// skipping the whole chunk.
                if mask == 0 {
                    idx &+= 8
                    continue
                }

                /// The lowest set bit marks the first `.` in the chunk; dividing its bit position
                /// by 8 turns it back into a byte offset.
                let dotIndex = idx &+ (mask.trailingZeroBitCount &>> 3)
                /// The label ends right before this `.`, so record its length.
                maxLabelLength = max(maxLabelLength, dotIndex &- startIndex)
                /// The next label starts right after this `.`, which is also where the next word
                /// load resumes. Any later `.` in this chunk is found by that reload instead.
                startIndex = dotIndex &+ 1
                idx = startIndex
            }

            /// Measure the remaining fewer-than-8 bytes one at a time.
            while idx < count {
                /// Same measuring as above, but for a single byte.
                if unsafe base.loadUnaligned(fromByteOffset: idx, as: UInt8.self) == .asciiDot {
                    maxLabelLength = max(maxLabelLength, idx &- startIndex)
                    startIndex = idx &+ 1
                }
                idx &+= 1
            }

            /// The final label has no trailing `.`, so it ends at `count`.
            return max(maxLabelLength, count &- startIndex)
        }
    }

    /// https://www.unicode.org/reports/tr46/#ProcessingStepConvertValidate
    /// Returns true if succeeded.
    @inlinable
    func convertAndValidateLabel(
        _ span: Span<UInt8>,
        scalarsIndexToUTF8IndexForReuse: inout LazyRigidArray<Int>,
        newerBytes: inout TinyBuffer,
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

        var outputBuffer = TinyBufferSubsequence(
            base: newerBytes,
            startIndex: currentNewerBytesCount
        )
        if Punycode.decode(
            _uncheckedAssumingValidUTF8: unsafe span.extracting(unchecked: noXNRange),
            scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
            outputBuffer: &outputBuffer
        ) {
            newerBytes = outputBuffer.base

            let range = unsafe Range<Int>(
                uncheckedBounds: (currentNewerBytesCount, newerBytes.count)
            )

            newerBytes.withSpan { newerBytesSpan in
                let conversionSpan = unsafe newerBytesSpan.extracting(unchecked: range)

                /// 4.3:
                checkInvalidPunycode(span: conversionSpan, errors: &errors)

                verifyValidLabel(_uncheckedAssumingValidUTF8: conversionSpan, errors: &errors)
            }

            return true
        } else {
            newerBytes = outputBuffer.base

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
            !span.isInNFC
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
            let firstScalar = Unicode.Scalar(firstUncheckedScalar),
            firstScalar.properties.generalCategory.isMark == true
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
                guard let scalar = Unicode.Scalar(uncheckedScalar) else {
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
