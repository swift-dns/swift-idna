@available(swiftIDNAApplePlatforms 26, *)
extension IDNA {
    @usableFromInline
    enum ConversionResult {
        case noChanges
        case bytes([UInt8])
        case string(String)
        case modifiedInPlace
    }

    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @_lifetime(borrow utf8Span)
    func toASCII(
        utf8Span: UTF8Span,
        canModifyUTF8SpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        switch IDNA.performCharacterCheck(span: utf8Span.span) {
        case .containsOnlyIDNANoOpCharacters:
            if !utf8Span.span.containsIDNADomainNameMarkerLabelPrefix {
                return .noChanges
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !utf8Span.span.containsIDNADomainNameMarkerLabelPrefix {
                switch convertToLowercasedASCII(
                    utf8Span: utf8Span,
                    canModifyUTF8SpanBytes: canModifyUTF8SpanBytes
                ) {
                case .modifiedInPlace:
                    return .modifiedInPlace
                case .string(let string):
                    return .string(string)
                }
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(
            domainName: String(uncheckedUTF8Span: utf8Span.span)
        )

        // 1.
        let utf8Span = self.mainProcessing(utf8Span: utf8Span, errors: &errors)

        // 2., 3.

        var convertedBytes: [UInt8] = []
        var startIndex = 0
        let bytesSpan = utf8Span.span
        for idx in bytesSpan.indices {
            /// If this is not a label separator, then continue
            var endIndex = idx
            let countBehindX = idx
            switch countBehindX {
            case 0, 1, 2:
                guard bytesSpan[unchecked: idx] == .asciiDot else {
                    continue
                }
            case 3...:
                let third = bytesSpan[unchecked: idx]
                let second = bytesSpan[unchecked: idx &- 1]
                let first = bytesSpan[unchecked: idx &- 2]
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
                domainNameSpan: bytesSpan,
                startIndex: startIndex,
                endIndex: endIndex,
                appendDot: true,
                convertedBytes: &convertedBytes,
                errors: &errors
            )

            startIndex = idx &+ 1
        }

        /// Last label
        appendLabel(
            domainNameSpan: bytesSpan,
            startIndex: startIndex,
            endIndex: bytesSpan.count,
            appendDot: false,
            convertedBytes: &convertedBytes,
            errors: &errors
        )

        if configuration.verifyDNSLength {
            if convertedBytes.count >= 254 {
                errors.append(
                    .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
                        length: convertedBytes.count,
                        labels: [Substring(String(uncheckedUTF8Span: convertedBytes.span))]
                    )
                )
            }
            if convertedBytes.isEmpty {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(
                        labels: [Substring(String(uncheckedUTF8Span: convertedBytes.span))]
                    )
                )
            }
        }

        if !errors.isEmpty {
            throw errors
        }

        return .bytes(convertedBytes)
    }

    func appendLabel(
        domainNameSpan bytesSpan: Span<UInt8>,
        startIndex: Int,
        endIndex: Int,
        appendDot: Bool,
        convertedBytes: inout [UInt8],
        errors: inout MappingErrors
    ) {
        let range = Range<Int>(uncheckedBounds: (startIndex, endIndex))
        let labelSpan = bytesSpan.extracting(unchecked: range)
        var labelByteLength = 0
        if labelSpan.allSatisfy(\.isASCII) {
            if !labelSpan.isEmpty {
                convertedBytes.reserveCapacity(labelSpan.count + 1)
                convertedBytes.append(span: labelSpan)
                labelByteLength = labelSpan.count
            }
            if appendDot {
                convertedBytes.append(.asciiDot)
            }
        } else {
            print(
                "to_ASCII label before Punycode:",
                String(uncheckedUTF8Span: labelSpan).debugDescription
            )
            let newBytes = Punycode.encode(uncheckedUTF8Span: labelSpan)
            print(
                "to_ASCII label after Punycode:",
                String(uncheckedUTF8Span: newBytes.span).debugDescription
            )
            convertedBytes.reserveCapacity(4 + newBytes.count + 1)
            convertedBytes.append(contentsOf: "xn--".utf8)
            convertedBytes.append(span: newBytes.span)
            labelByteLength = 4 + newBytes.count
            if appendDot {
                convertedBytes.append(.asciiDot)
            }
        }

        if configuration.verifyDNSLength {
            if labelByteLength > 63 {
                errors.append(
                    .trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(
                        length: labelByteLength,
                        label: Substring(String(uncheckedUTF8Span: labelSpan))
                    )
                )
            }

            if labelByteLength == 0 {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(
                        label: Substring(String(uncheckedUTF8Span: labelSpan))
                    )
                )
            }
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    @_lifetime(borrow utf8Span)
    func toUnicode(
        utf8Span: UTF8Span,
        canModifyUTF8SpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        switch IDNA.performCharacterCheck(span: utf8Span.span) {
        case .containsOnlyIDNANoOpCharacters:
            if !utf8Span.span.containsIDNADomainNameMarkerLabelPrefix {
                return .noChanges
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !utf8Span.span.containsIDNADomainNameMarkerLabelPrefix {
                switch convertToLowercasedASCII(
                    utf8Span: utf8Span,
                    canModifyUTF8SpanBytes: canModifyUTF8SpanBytes
                ) {
                case .modifiedInPlace:
                    return .modifiedInPlace
                case .string(let string):
                    return .string(string)
                }
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(
            domainName: String(uncheckedUTF8Span: utf8Span.span)
        )

        // 1.
        let newBytes = self.mainProcessing(utf8Span: utf8Span, errors: &errors)

        // 2.
        if !errors.isEmpty {
            throw errors
        }

        return .bytes(newBytes)
    }

    /// Main `Processing` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#Processing
    @_lifetime(borrow utf8Span)
    @usableFromInline
    func mainProcessing(utf8Span: UTF8Span, errors: inout MappingErrors) -> [UInt8] {
        var newBytes: [UInt8] = []
        /// TODO: optimize reserve capacity
        newBytes.reserveCapacity(utf8Span.count * 14 / 10)

        var unicodeScalarsIterator = utf8Span.makeUnicodeScalarIterator()

        /// 1. Map
        while let scalar = unicodeScalarsIterator.next() {
            switch IDNAMapping.for(scalar: scalar) {
            case .valid(_):
                newBytes.append(contentsOf: scalar.utf8)
            case .mapped(let mappedScalars):
                for mappedScalar in mappedScalars {
                    newBytes.append(contentsOf: mappedScalar.utf8)
                }
            case .deviation(_):
                newBytes.append(contentsOf: scalar.utf8)
            case .disallowed:
                newBytes.append(contentsOf: scalar.utf8)
            case .ignored:
                break
            }
        }

        /// 2. Normalize
        var newerBytes: [UInt8] = []

        /// Make `newBytes` NFC, if not already NFC
        if let nfcNewBytes = newBytes.withUnsafeBufferPointer({
            newBytesBuffer -> [UInt8]? in
            let newBytesSpan = newBytesBuffer.span
            /// We just replaced some unicode scalars with some other unicode scalars,
            /// so unchecked is fine.
            var newBytesUTF8Span = UTF8Span(unchecked: newBytesSpan)
            if !newBytesUTF8Span.checkForNFC(quickCheck: false) {
                return String(uncheckedUTF8Span: newBytesSpan).nfcCodePoints
            } else {
                return nil
            }
        }) {
            newBytes = nfcNewBytes
        }

        newBytes.withUnsafeBufferPointer { newBytesBuffer in
            let newBytesSpan = newBytesBuffer.span

            var startIndex = 0
            for idx in newBytesSpan.indices {
                guard newBytesSpan[unchecked: idx] == .asciiDot else {
                    continue
                }

                let range = Range<Int>(uncheckedBounds: (startIndex, idx))
                let chunk = newBytesSpan.extracting(unchecked: range)
                switchStatement: switch convertAndValidateLabel(chunk, errors: &errors) {
                case .span(let labelSpan):
                    newerBytes.append(span: labelSpan)
                    newerBytes.append(.asciiDot)
                case .bytes(let bytes):
                    newerBytes.append(contentsOf: bytes)
                    newerBytes.append(.asciiDot)

                    print(
                        "after bytes in mainProcessing",
                        String(uncheckedUTF8Span: bytes.span).debugDescription,
                        String(uncheckedUTF8Span: newBytes.span).debugDescription
                    )
                case .failure:
                    break switchStatement
                }

                startIndex = idx &+ 1
            }

            let range = Range<Int>(uncheckedBounds: (startIndex, newBytesSpan.count))
            let chunk = newBytesSpan.extracting(unchecked: range)
            switchStatement: switch convertAndValidateLabel(chunk, errors: &errors) {
            case .span(let labelSpan):
                newerBytes.append(span: labelSpan)
            case .bytes(let bytes):
                newerBytes.append(contentsOf: bytes)

                print(
                    "after bytes in mainProcessing",
                    String(uncheckedUTF8Span: bytes.span).debugDescription,
                    String(uncheckedUTF8Span: newBytes.span).debugDescription
                )
            case .failure:
                break switchStatement
            }
        }

        return newerBytes
    }

    @usableFromInline
    enum ConvertAndValidateResult: ~Escapable {
        case span(Span<UInt8>)
        case bytes([UInt8])
        case failure
    }

    /// https://www.unicode.org/reports/tr46/#ProcessingStepConvertValidate
    @_lifetime(copy span)
    @usableFromInline
    func convertAndValidateLabel(
        _ span: Span<UInt8>,
        errors: inout MappingErrors
    ) -> ConvertAndValidateResult {
        /// Checks if the label starts with “xn--”
        guard span.hasIDNADomainNameMarkerPrefix else {
            verifyValidLabel(uncheckedUTF8Span: span, errors: &errors)
            return .span(span)
        }

        /// 4.1:
        if !configuration.ignoreInvalidPunycode,
            span.contains(where: { !$0.isASCII })
        {
            errors.append(
                .labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(
                    label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                )
            )
            /// continue to next label
            return .failure
        }

        /// 4.2:
        /// If conversion fails, and we're not ignoring invalid punycode, record an error

        /// Drop the "xn--" prefix
        let noXNRange = Range<Int>(uncheckedBounds: (4, span.count))
        if let conversionResult = Punycode.decode(
            uncheckedUTF8Span: span.extracting(unchecked: noXNRange)
        ) {
            /// 4.3:
            checkInvalidPunycode(span: conversionResult.span, errors: &errors)

            print(
                "after conversion in convertAndValidateLabel",
                String(uncheckedUTF8Span: conversionResult.span).debugDescription
            )

            verifyValidLabel(uncheckedUTF8Span: conversionResult.span, errors: &errors)

            print(
                "after verifyValidLabel in convertAndValidateLabel",
                String(uncheckedUTF8Span: conversionResult.span).debugDescription
            )

            return .bytes(conversionResult)
        } else {
            switch configuration.ignoreInvalidPunycode {
            case true:
                /// Use the original label

                /// 4.3:
                checkInvalidPunycode(span: span, errors: &errors)

                verifyValidLabel(uncheckedUTF8Span: span, errors: &errors)

                return .span(span)
            case false:
                errors.append(
                    .labelPunycodeDecodeFailed(
                        label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                    )
                )
                /// continue to next label
                return .failure
            }
        }
    }

    func checkInvalidPunycode(span: Span<UInt8>, errors: inout MappingErrors) {
        if configuration.ignoreInvalidPunycode {
            return
        }

        if span.isEmpty {
            errors.append(
                .labelIsEmptyAfterPunycodeConversion(
                    label: Substring(String(uncheckedUTF8Span: span))
                )
            )
        }

        if span.allSatisfy(\.isASCII) {
            errors.append(
                .labelContainsOnlyASCIIAfterPunycodeDecode(
                    label: Substring(String(uncheckedUTF8Span: span))
                )
            )
        }
    }

    /// https://www.unicode.org/reports/tr46/#Validity_Criteria
    @usableFromInline
    func verifyValidLabel(uncheckedUTF8Span span: Span<UInt8>, errors: inout MappingErrors) {
        var utf8Span = UTF8Span(unchecked: span)

        if !configuration.ignoreInvalidPunycode,
            !utf8Span.checkForNFC(quickCheck: false)
        {
            errors.append(
                .labelIsNotInNormalizationFormC(
                    label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                )
            )
        }

        switch configuration.checkHyphens {
        case true:
            let bytesCount = span.count
            if bytesCount >= 4,
                span[unchecked: 2] == UInt8.asciiHyphenMinus,
                span[unchecked: 3] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(
                        label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                    )
                )
            }
            if bytesCount >= 1,
                span[unchecked: 0] == UInt8.asciiHyphenMinus
                    || span[unchecked: bytesCount - 1] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(
                        label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                    )
                )
            }
        case false:
            if !configuration.ignoreInvalidPunycode,
                span.hasIDNADomainNameMarkerPrefix
            {
                errors.append(
                    .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                        label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                    )
                )
            }
        }

        var unicodeScalarsIterator = utf8Span.makeUnicodeScalarIterator()
        let startingCodeUnitOffset = unicodeScalarsIterator.currentCodeUnitOffset
        if !configuration.ignoreInvalidPunycode,
            let firstScalar = unicodeScalarsIterator.next(),
            firstScalar.properties.generalCategory.isMark == true
        {
            errors.append(
                .labelStartsWithCombiningMark(
                    label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                )
            )
        }

        if !configuration.ignoreInvalidPunycode {
            unicodeScalarsIterator.reset(toUnchecked: startingCodeUnitOffset)

            while let codePoint = unicodeScalarsIterator.next() {
                switch IDNAMapping.for(scalar: codePoint) {
                case .valid, .deviation:
                    break
                case .mapped, .disallowed, .ignored:
                    errors.append(
                        .labelContainsInvalidUnicode(
                            codePoint,
                            label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                        )
                    )
                }
            }
        }

        /// TODO: combine this step with the step above, to not have to iterate over unicode scalars twice
        if configuration.useSTD3ASCIIRules {
            unicodeScalarsIterator.reset(toUnchecked: startingCodeUnitOffset)

            while let codePoint = unicodeScalarsIterator.next() {
                if codePoint.isASCII,
                    !codePoint.isNumberOrLowercasedLetterOrHyphenMinusASCII
                {
                    errors.append(
                        .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                            label: .init(String(uncheckedUTF8Span: span).unicodeScalars)
                        )
                    )
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

    @usableFromInline
    enum ConvertToLowercasedASCIIResult {
        case string(String)
        case modifiedInPlace
    }

    @usableFromInline
    func convertToLowercasedASCII(
        utf8Span: UTF8Span,
        canModifyUTF8SpanBytes: Bool
    ) -> ConvertToLowercasedASCIIResult {
        let span = utf8Span.span
        let bytesCount = span.count
        if !canModifyUTF8SpanBytes || bytesCount < 16 {
            /// _SmallString path
            let string = String(unsafeUninitializedCapacity: bytesCount) { stringBuffer in
                for idx in span.indices {
                    stringBuffer[idx] = span[unchecked: idx].toLowercasedASCIILetter()
                }
                return bytesCount
            }
            return .string(string)
        } else {
            span.withUnsafeBufferPointer {
                let mutableStringBuffer = UnsafeMutableBufferPointer(mutating: $0)
                for idx in mutableStringBuffer.indices {
                    mutableStringBuffer[idx] = mutableStringBuffer[idx].toLowercasedASCIILetter()
                }
            }
            return .modifiedInPlace
        }
    }
}
