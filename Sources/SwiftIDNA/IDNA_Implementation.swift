public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @inlinable
    @_lifetime(borrow span)
    func _toASCII(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(CollectedMappingErrors) -> ConversionResult {
        switch IDNA.performByteCheck(on: span) {
        case .containsOnlyIDNANoOpCharacters:
            return .noChangedNeeded
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            let string = convertToLowercasedASCII(_uncheckedAssumingValidUTF8: span)
            return .string(string)
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainNameSpan: span)

        // 1.
        var convertedBytes = UniqueArray<UInt8>()
        let utf8Bytes = self.mainProcessing(
            _uncheckedAssumingValidUTF8: span,
            reuseBuffer: &convertedBytes,
            errors: &errors
        )

        // 2., 3.
        var outputBufferForReuse = LazyUniqueArray<UInt8>(
            capacity: convertedBytes.count
        )

        /// TODO: Use a tiny-array here?
        convertedBytes.removeAll(keepingCapacity: true)
        convertedBytes.reserveCapacity(convertedBytes.count + span.count)

        let bytesSpan = utf8Bytes.span

        var startIndex = 0

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
                outputBufferForReuse: &outputBufferForReuse,
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
            outputBufferForReuse: &outputBufferForReuse,
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
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(
                        labels: [UInt8](copying: convertedBytes.span)
                    )
                )
            }
        }

        if !errors.isEmpty {
            throw CollectedMappingErrors(mappingErrors: errors)
        }

        return .bytes(convertedBytes)
    }

    @inlinable
    @_lifetime(&errors)
    func appendLabel(
        domainNameSpan bytesSpan: Span<UInt8>,
        startIndex: Int,
        endIndex: Int,
        appendDot: Bool,
        convertedBytes: inout UniqueArray<UInt8>,
        outputBufferForReuse: inout LazyUniqueArray<UInt8>,
        errors: inout MappingErrors
    ) {
        let range = Range<Int>(uncheckedBounds: (startIndex, endIndex))
        let labelSpan = bytesSpan.extracting(unchecked: range)
        var labelByteLength = 0
        if labelSpan.isASCII {
            if !labelSpan.isEmpty {
                convertedBytes.reserveCapacity(convertedBytes.count + labelSpan.count + 1)
                convertedBytes.append(copying: labelSpan)
                labelByteLength = labelSpan.count
            }
            if appendDot {
                convertedBytes.append(.asciiDot)
            }
        } else {
            /// TODO: can we pass convertedBytes to Punycode.encode instead of it returning a new array?
            outputBufferForReuse.withUniqueArray { outputBufferForReuse in
                Punycode.encode(
                    _uncheckedAssumingValidUTF8: labelSpan,
                    outputBufferForReuse: &outputBufferForReuse
                )

                convertedBytes.reserveCapacity(
                    convertedBytes.count + 4 + outputBufferForReuse.count + 1
                )
                convertedBytes.append(copying: "xn--".utf8)
                convertedBytes.append(copying: outputBufferForReuse.span)
                labelByteLength = 4 + outputBufferForReuse.count
                if appendDot {
                    convertedBytes.append(.asciiDot)
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

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    @inlinable
    @_lifetime(borrow span)
    func _toUnicode(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) throws(CollectedMappingErrors) -> ConversionResult {
        switch IDNA.performByteCheck(on: span) {
        case .containsOnlyIDNANoOpCharacters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                return .noChangedNeeded
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                let string = convertToLowercasedASCII(_uncheckedAssumingValidUTF8: span)
                return .string(string)
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainNameSpan: span)

        // 1.
        var reuseBuffer = UniqueArray<UInt8>()
        let utf8Bytes = self.mainProcessing(
            _uncheckedAssumingValidUTF8: span,
            reuseBuffer: &reuseBuffer,
            errors: &errors
        )

        // 2.
        if !errors.isEmpty {
            throw CollectedMappingErrors(mappingErrors: errors)
        }

        return .bytes(utf8Bytes)
    }

    /// Main `Processing` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#Processing
    @inlinable
    @_lifetime(&errors)
    func mainProcessing(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>,
        reuseBuffer newBytes: inout UniqueArray<UInt8>,
        errors: inout MappingErrors
    ) -> UniqueArray<UInt8> {
        /// 1. Map
        self.idnaMapBytes(
            _uncheckedAssumingValidUTF8: span,
            into: &newBytes
        )

        /// 2. Normalize

        /// Make `newBytes` NFC, if not already NFC
        newBytes._uncheckedAssumingValidUTF8_ensureNFC()

        var newerBytes = UniqueArray<UInt8>()
        newerBytes.reserveCapacity(newBytes.count)

        newBytes.span.withUnsafeBufferPointer { newBytesBuffer in
            let newBytesSpan = newBytesBuffer.span

            let maxRequiredCapacityForAllLabels = self.maxLabelLength(span: newBytesSpan)
            var scalarsIndexToUTF8IndexForReuse = LazyRigidArray<Int>(
                capacity: maxRequiredCapacityForAllLabels
            )

            var startIndex = 0
            for idx in newBytesSpan.indices {
                /// Unchecked because idx comes right from `newBytesSpan.indices`
                guard newBytesSpan[unchecked: idx] == .asciiDot else {
                    continue
                }

                let range = Range<Int>(uncheckedBounds: (startIndex, idx))
                let chunk = newBytesSpan.extracting(unchecked: range)

                if convertAndValidateLabel(
                    chunk,
                    scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
                    newerBytes: &newerBytes,
                    errors: &errors
                ) {
                    newerBytes.append(.asciiDot)
                }

                startIndex = idx &+ 1
            }

            let range = Range<Int>(uncheckedBounds: (startIndex, newBytesSpan.count))
            let chunk = newBytesSpan.extracting(unchecked: range)
            _ = convertAndValidateLabel(
                chunk,
                scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
                newerBytes: &newerBytes,
                errors: &errors
            )
        }

        return newerBytes
    }

    @inlinable
    func idnaMapBytes(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>,
        into newBytes: inout UniqueArray<UInt8>
    ) {
        /// I'm expecting this to be empty, nothing special.
        /// Tests will immediately crash if this is not the case.
        assert(newBytes.isEmpty)

        var requiredCapacity = 0

        var unicodeScalarsIterator = span.makeUnicodeScalarIterator_Compatibility()

        while let scalar = unicodeScalarsIterator.next() {
            switch IDNAMapping.for(scalar: scalar) {
            case .valid(_):
                requiredCapacity &+= scalar.utf8.count
            case .mapped(let mappedScalars):
                for mappedScalar in mappedScalars {
                    requiredCapacity &+= mappedScalar.utf8.count
                }
            case .deviation(_):
                requiredCapacity &+= scalar.utf8.count
            case .disallowed:
                requiredCapacity &+= scalar.utf8.count
            case .ignored:
                break
            }
        }

        /// Use the underlying RigidArray to skip capacity checks because
        /// we're guaranteed to have enough capacity.
        var rigidArray = RigidArray(consuming: newBytes)
        rigidArray.reserveCapacity(requiredCapacity)

        unicodeScalarsIterator = span.makeUnicodeScalarIterator_Compatibility()

        while let scalar = unicodeScalarsIterator.next() {
            switch IDNAMapping.for(scalar: scalar) {
            case .valid(_):
                rigidArray.append(copying: scalar.utf8)
            case .mapped(let mappedScalars):
                for mappedScalar in mappedScalars {
                    rigidArray.append(copying: mappedScalar.utf8)
                }
            case .deviation(_):
                rigidArray.append(copying: scalar.utf8)
            case .disallowed:
                rigidArray.append(copying: scalar.utf8)
            case .ignored:
                break
            }
        }

        newBytes = UniqueArray(consuming: rigidArray)
    }

    @inlinable
    func maxLabelLength(span: Span<UInt8>) -> Int {
        var maxLabelLength = 0
        var startIndex = 0

        for idx in span.indices {
            /// Unchecked because idx comes right from `newBytesSpan.indices`
            guard span[unchecked: idx] == .asciiDot else {
                continue
            }

            maxLabelLength = max(
                maxLabelLength,
                idx - startIndex
            )
            startIndex = idx &+ 1
        }

        maxLabelLength = max(
            maxLabelLength,
            span.count - startIndex
        )

        return maxLabelLength
    }

    /// https://www.unicode.org/reports/tr46/#ProcessingStepConvertValidate
    /// Returns true if succeeded.
    @inlinable
    @_lifetime(copy span)
    func convertAndValidateLabel(
        _ span: Span<UInt8>,
        scalarsIndexToUTF8IndexForReuse: inout LazyRigidArray<Int>,
        newerBytes: inout UniqueArray<UInt8>,
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
                    label: String(_uncheckedAssumingValidUTF8: span)
                )
            )
            /// continue to next label
            return false
        }

        /// 4.2:
        /// If conversion fails, and we're not ignoring invalid punycode, record an error

        /// Drop the "xn--" prefix
        let noXNRange = Range<Int>(uncheckedBounds: (4, span.count))
        let currentNewerBytesCount = newerBytes.count

        var outputBuffer = UniqueArraySubSequence<UInt8>(
            base: newerBytes,
            startIndex: currentNewerBytesCount
        )
        if Punycode.decode(
            _uncheckedAssumingValidUTF8: span.extracting(unchecked: noXNRange),
            scalarsIndexToUTF8IndexForReuse: &scalarsIndexToUTF8IndexForReuse,
            outputBuffer: &outputBuffer
        ) {
            newerBytes = outputBuffer.base

            let range = Range<Int>(
                uncheckedBounds: (currentNewerBytesCount, newerBytes.count)
            )
            let conversionSpan = newerBytes.span.extracting(unchecked: range)

            /// 4.3:
            checkInvalidPunycode(span: conversionSpan, errors: &errors)

            verifyValidLabel(_uncheckedAssumingValidUTF8: conversionSpan, errors: &errors)

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
                        label: String(_uncheckedAssumingValidUTF8: span)
                    )
                )
                /// continue to next label
                return false
            }
        }
    }

    @inlinable
    @_lifetime(&errors)
    func checkInvalidPunycode(span: Span<UInt8>, errors: inout MappingErrors) {
        if configuration.ignoreInvalidPunycode {
            return
        }

        if span.isEmpty {
            errors.append(
                .labelIsEmptyAfterPunycodeConversion(
                    label: String(_uncheckedAssumingValidUTF8: span)
                )
            )
        }

        if span.isASCII {
            errors.append(
                .labelContainsOnlyASCIIAfterPunycodeDecode(
                    label: String(_uncheckedAssumingValidUTF8: span)
                )
            )
        }
    }

    /// https://www.unicode.org/reports/tr46/#Validity_Criteria
    @inlinable
    @_lifetime(&errors)
    func verifyValidLabel(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>,
        errors: inout MappingErrors
    ) {
        if !configuration.ignoreInvalidPunycode,
            !span.isInNFC
        {
            errors.append(
                .labelIsNotInNormalizationFormC(
                    label: String(_uncheckedAssumingValidUTF8: span)
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
                        label: String(_uncheckedAssumingValidUTF8: span)
                    )
                )
            }
            if bytesCount >= 1,
                span[unchecked: 0] == UInt8.asciiHyphenMinus
                    || span[unchecked: bytesCount - 1] == UInt8.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(
                        label: String(_uncheckedAssumingValidUTF8: span)
                    )
                )
            }
        case false:
            if !configuration.ignoreInvalidPunycode,
                span.hasIDNADomainNameMarkerPrefix
            {
                errors.append(
                    .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                        label: String(_uncheckedAssumingValidUTF8: span)
                    )
                )
            }
        }

        var unicodeScalarsIterator = span.makeUnicodeScalarIterator_Compatibility()
        if !configuration.ignoreInvalidPunycode,
            let firstScalar = unicodeScalarsIterator.next(),
            firstScalar.properties.generalCategory.isMark == true
        {
            errors.append(
                .labelStartsWithCombiningMark(
                    label: String(_uncheckedAssumingValidUTF8: span)
                )
            )
        }

        if !configuration.ignoreInvalidPunycode || configuration.useSTD3ASCIIRules {
            var unicodeScalarsIterator = span.makeUnicodeScalarIterator_Compatibility()

            while let codePoint = unicodeScalarsIterator.next() {
                if !configuration.ignoreInvalidPunycode {
                    switch IDNAMapping.for(scalar: codePoint) {
                    case .valid, .deviation:
                        break
                    case .mapped, .disallowed, .ignored:
                        errors.append(
                            .labelContainsInvalidUnicode(
                                codePoint,
                                label: String(_uncheckedAssumingValidUTF8: span)
                            )
                        )
                    }
                }

                if configuration.useSTD3ASCIIRules {
                    if codePoint.isASCII,
                        !codePoint.value.isLowercasedLetterOrDigitOrHyphenMinus
                    {
                        errors.append(
                            .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                                label: String(_uncheckedAssumingValidUTF8: span)
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
    func convertToLowercasedASCII(_uncheckedAssumingValidUTF8 span: Span<UInt8>) -> String {
        let count = span.count
        return String(unsafeUninitializedCapacity_Compatibility: count) { buffer in
            for idx in 0..<count {
                buffer[idx] = span[unchecked: idx].toLowercasedASCIILetter()
            }
            return count
        }
    }
}
