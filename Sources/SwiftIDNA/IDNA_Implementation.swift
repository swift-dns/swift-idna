@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @_lifetime(copy span)
    func _toASCII(
        uncheckedUTF8Span span: Span<UInt8>,
        canInPlaceModifySpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        switch IDNA.performCharacterCheck(span: span) {
        case .containsOnlyIDNANoOpCharacters:
            return .noChangedNeeded
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            switch convertToLowercasedASCII(
                uncheckedUTF8Span: span,
                canInPlaceModifySpanBytes: canInPlaceModifySpanBytes
            ) {
            case .modifiedInPlace:
                return .noChangedNeeded
            case .string(let string):
                return .string(string)
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(
            domainName: String(uncheckedUTF8Span: span)
        )

        // 1.
        let utf8Bytes = self.mainProcessing(uncheckedUTF8Span: span, errors: &errors)

        // 2., 3.

        var convertedBytes: [UInt8] = []
        var startIndex = 0
        utf8Bytes.withSpan_Compatibility { bytesSpan in
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
        }

        if configuration.verifyDNSLength {
            if convertedBytes.count >= 254 {
                convertedBytes.withSpan_Compatibility { span in
                    errors.append(
                        .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
                            length: convertedBytes.count,
                            labels: convertedBytes
                        )
                    )
                }
            }
            if convertedBytes.isEmpty {
                convertedBytes.withSpan_Compatibility { span in
                    errors.append(
                        .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(
                            labels: convertedBytes
                        )
                    )
                }
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
            /// TODO: can we pass convertedBytes to Punycode.encode instead of it returning a new array?
            let newBytes = Punycode.encode(uncheckedUTF8Span: labelSpan)
            convertedBytes.reserveCapacity(4 + newBytes.count + 1)
            convertedBytes.append(contentsOf: "xn--".utf8)
            newBytes.withSpan_Compatibility { span in
                convertedBytes.append(span: span)
            }
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
                        labels: convertedBytes
                    )
                )
            }

            if labelByteLength == 0 {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(
                        labels: convertedBytes
                    )
                )
            }
        }
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    @_lifetime(copy span)
    func _toUnicode(
        uncheckedUTF8Span span: Span<UInt8>,
        canInPlaceModifySpanBytes: Bool
    ) throws(MappingErrors) -> ConversionResult {
        switch IDNA.performCharacterCheck(span: span) {
        case .containsOnlyIDNANoOpCharacters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                return .noChangedNeeded
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                switch convertToLowercasedASCII(
                    uncheckedUTF8Span: span,
                    canInPlaceModifySpanBytes: canInPlaceModifySpanBytes
                ) {
                case .modifiedInPlace:
                    return .noChangedNeeded
                case .string(let string):
                    return .string(string)
                }
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(
            domainName: String(uncheckedUTF8Span: span)
        )

        // 1.
        let newBytes = self.mainProcessing(uncheckedUTF8Span: span, errors: &errors)

        // 2.
        if !errors.isEmpty {
            throw errors
        }

        return .bytes(newBytes)
    }

    /// Main `Processing` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#Processing
    @_lifetime(copy span)
    @usableFromInline
    func mainProcessing(
        uncheckedUTF8Span span: Span<UInt8>,
        errors: inout MappingErrors
    ) -> [UInt8] {
        var newBytes: [UInt8] = []
        /// TODO: optimize reserve capacity
        newBytes.reserveCapacity(span.count * 14 / 10)

        var unicodeScalarsIterator = span.makeUnicodeScalarIteratorCompatibility()

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

        /// Make `newBytes` NFC, if not already NFC
        newBytes.uncheckedUTF8Bytes_ensureNFC()

        var newerBytes: [UInt8] = []

        newBytes.withUnsafeBufferPointer { newBytesBuffer in
            let newBytesSpan = newBytesBuffer.span

            var startIndex = 0
            for idx in newBytesSpan.indices {
                /// Unchecked because idx comes right from `newBytesSpan.indices`
                guard newBytesSpan[unchecked: idx] == .asciiDot else {
                    continue
                }

                let range = Range<Int>(uncheckedBounds: (startIndex, idx))
                let chunk = newBytesSpan.extracting(unchecked: range)
                /// TODO: can we pass newerBytes to convertAndValidateLabel instead of it returning a new buffer?!
                switchStatement: switch convertAndValidateLabel(chunk, errors: &errors) {
                case .span(let labelSpan):
                    newerBytes.append(span: labelSpan)
                    newerBytes.append(.asciiDot)
                case .bytes(let bytes):
                    newerBytes.append(contentsOf: bytes)
                    newerBytes.append(.asciiDot)
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
                    label: String(uncheckedUTF8Span: span)
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
            let conversionResult = conversionResult.withSpan_Compatibility { conversionSpan in
                /// 4.3:
                checkInvalidPunycode(span: conversionSpan, errors: &errors)

                verifyValidLabel(uncheckedUTF8Span: conversionSpan, errors: &errors)

                return conversionResult
            }
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
                        label: String(uncheckedUTF8Span: span)
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
                    label: String(uncheckedUTF8Span: span)
                )
            )
        }

        if span.allSatisfy(\.isASCII) {
            errors.append(
                .labelContainsOnlyASCIIAfterPunycodeDecode(
                    label: String(uncheckedUTF8Span: span)
                )
            )
        }
    }

    /// https://www.unicode.org/reports/tr46/#Validity_Criteria
    @usableFromInline
    func verifyValidLabel(uncheckedUTF8Span span: Span<UInt8>, errors: inout MappingErrors) {

        var spanString: String?
        func getSpanString() -> String {
            if let spanString = spanString {
                return spanString
            }
            spanString = String(uncheckedUTF8Span: span)
            return spanString!
        }

        if !configuration.ignoreInvalidPunycode,
            !span.isInNFC
        {
            errors.append(.labelIsNotInNormalizationFormC(label: getSpanString()))
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
                        label: getSpanString()
                    )
                )
            }
            if bytesCount >= 1,
                span[unchecked: 0] == UInt8.asciiHyphenMinus
                    || span[unchecked: bytesCount - 1] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(
                        label: getSpanString()
                    )
                )
            }
        case false:
            if !configuration.ignoreInvalidPunycode,
                span.hasIDNADomainNameMarkerPrefix
            {
                errors.append(
                    .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                        label: getSpanString()
                    )
                )
            }
        }

        var unicodeScalarsIterator = span.makeUnicodeScalarIteratorCompatibility()
        if !configuration.ignoreInvalidPunycode,
            let firstScalar = unicodeScalarsIterator.next(),
            firstScalar.properties.generalCategory.isMark == true
        {
            errors.append(
                .labelStartsWithCombiningMark(
                    label: getSpanString()
                )
            )
        }

        if !configuration.ignoreInvalidPunycode || configuration.useSTD3ASCIIRules {
            var unicodeScalarsIterator = span.makeUnicodeScalarIteratorCompatibility()

            while let codePoint = unicodeScalarsIterator.next() {
                if !configuration.ignoreInvalidPunycode {
                    switch IDNAMapping.for(scalar: codePoint) {
                    case .valid, .deviation:
                        break
                    case .mapped, .disallowed, .ignored:
                        errors.append(
                            .labelContainsInvalidUnicode(codePoint, label: getSpanString())
                        )
                    }
                }

                if configuration.useSTD3ASCIIRules {
                    if codePoint.isASCII,
                        !codePoint.isNumberOrLowercasedLetterOrHyphenMinusASCII
                    {
                        errors.append(
                            .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                                label: getSpanString()
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

    @usableFromInline
    enum ConvertToLowercasedASCIIResult {
        case string(String)
        case modifiedInPlace
    }

    @usableFromInline
    func convertToLowercasedASCII(
        uncheckedUTF8Span span: Span<UInt8>,
        canInPlaceModifySpanBytes: Bool
    ) -> ConvertToLowercasedASCIIResult {
        if canInPlaceModifySpanBytes {
            span.withUnsafeBufferPointer {
                let mutableStringBuffer = UnsafeMutableBufferPointer(mutating: $0)
                var idx = 0
                while idx < mutableStringBuffer.count {
                    mutableStringBuffer[idx] = mutableStringBuffer[idx].toLowercasedASCIILetter()
                    idx &+= 1
                }
            }
            return .modifiedInPlace
        } else {
            let bytesCount = span.count
            let string = String(unsafeUninitializedCapacity: bytesCount) { stringBuffer in
                var idx = 0
                while idx < bytesCount {
                    stringBuffer[idx] = span[unchecked: idx].toLowercasedASCIILetter()
                    idx &+= 1
                }
                return bytesCount
            }
            return .string(string)
        }
    }
}
