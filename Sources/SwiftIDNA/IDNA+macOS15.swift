extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    func toASCII_macOS15(domainName: inout String) throws(MappingErrors) {
        switch IDNA.performCharacterCheck(string: domainName) {
        case .containsOnlyIDNANoOpCharacters:
            return
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            convertToLowercasedASCII(domainName: &domainName)
            return
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainName: domainName)

        // 1.
        self.mainProcessing(domainName: &domainName, errors: &errors)

        // 2., 3.
        var labels = domainName.unicodeScalars.split(
            separator: Unicode.Scalar.asciiDot,
            omittingEmptySubsequences: false
        ).map { label -> Substring in
            if label.allSatisfy(\.isASCII) {
                return Substring(label)
            }
            var newLabel = Substring(label)
            if !Punycode.encode(&newLabel) {
                errors.append(.labelPunycodeEncodeFailed(label: label))
            }
            return "xn--" + Substring(newLabel)
        }

        if configuration.verifyDNSLength {
            if labels.last?.isEmpty == true {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyRootLabelWithTrailingDot(
                        labels: labels
                    )
                )
                labels.removeLast()
            }

            var totalByteLength = 0
            for label in labels {
                /// All scalars are already ASCII so each scalar is 1 byte
                /// So each scalar will only count 1 towards the DNS Domain Name byte limit
                let labelByteLength = label.unicodeScalars.count
                totalByteLength += labelByteLength
                if labelByteLength > 63 {
                    errors.append(
                        .trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(
                            length: labelByteLength,
                            label: label
                        )
                    )
                }
                if labelByteLength == 0 {
                    errors.append(
                        .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(label: label)
                    )
                }
            }

            let dnsLength = totalByteLength + labels.count
            if dnsLength > 254 {
                errors.append(
                    .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
                        length: dnsLength,
                        labels: labels
                    )
                )
            }
            if totalByteLength == 0 {
                errors.append(
                    .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(labels: labels)
                )
            }
        }

        if !errors.isEmpty {
            throw errors
        }

        domainName = labels.joined(separator: ".")
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    func toUnicode_macOS15(domainName: inout String) throws(MappingErrors) {
        switch IDNA.performCharacterCheck(string: domainName) {
        case .containsOnlyIDNANoOpCharacters:
            if !domainName.unicodeScalars.containsIDNADomainNameMarkerLabelPrefix {
                return
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !domainName.unicodeScalars.containsIDNADomainNameMarkerLabelPrefix {
                convertToLowercasedASCII(domainName: &domainName)
                return
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainName: domainName)

        // 1.
        self.mainProcessing(domainName: &domainName, errors: &errors)

        // 2.
        if !errors.isEmpty {
            throw errors
        }
    }

    /// Main `Processing` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#Processing
    @usableFromInline
    func mainProcessing(domainName: inout String, errors: inout MappingErrors) {
        var newUnicodeScalars: [Unicode.Scalar] = []
        /// TODO: optimize reserve capacity
        newUnicodeScalars.reserveCapacity(domainName.unicodeScalars.count * 12 / 10)

        /// 1. Map
        for scalar in domainName.unicodeScalars {
            switch IDNAMapping.for(scalar: scalar) {
            case .valid(_):
                newUnicodeScalars.append(scalar)
            case .mapped(let mappedScalars):
                newUnicodeScalars.append(contentsOf: mappedScalars)
            case .deviation(_):
                newUnicodeScalars.append(scalar)
            case .disallowed:
                newUnicodeScalars.append(scalar)
            case .ignored:
                break
            }
        }

        /// 2. Normalize
        domainName = String(String.UnicodeScalarView(newUnicodeScalars))
        domainName = domainName.asNFC

        /// 3. Break, 4. Convert/Validate.
        domainName = domainName.unicodeScalars.split(
            separator: Unicode.Scalar.asciiDot,
            omittingEmptySubsequences: false
        ).map { label in
            Substring(convertAndValidateLabel(label, errors: &errors))
        }.joined(separator: ".")
    }

    /// https://www.unicode.org/reports/tr46/#ProcessingStepConvertValidate
    @usableFromInline
    func convertAndValidateLabel(
        _ label: Substring.UnicodeScalarView,
        errors: inout MappingErrors
    ) -> Substring.UnicodeScalarView {
        var newLabel = Substring(label)

        /// Checks if the label starts with “xn--”
        if label.hasIDNADomainNameMarkerPrefix {
            /// 4.1:
            if !configuration.ignoreInvalidPunycode,
                label.contains(where: { !$0.isASCII })
            {
                errors.append(
                    .labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(label: label)
                )
                return label/// continue to next label
            }

            /// 4.2:
            /// If conversion fails, and we're not ignoring invalid punycode, record an error

            /// Drop the "xn--" prefix
            newLabel = Substring(newLabel.unicodeScalars.dropFirst(4))

            let conversionResult = Punycode.decode(&newLabel)
            switch conversionResult {
            case true:
                break
            case false:
                switch configuration.ignoreInvalidPunycode {
                case true:
                    /// reset back to original label
                    newLabel = Substring(label)
                case false:
                    errors.append(.labelPunycodeDecodeFailed(label: label))
                    /// continue to next label
                    return label
                }
            }

            /// 4.3:
            if !configuration.ignoreInvalidPunycode {
                if newLabel.isEmpty {
                    errors.append(.labelIsEmptyAfterPunycodeConversion(label: newLabel))
                }

                if newLabel.allSatisfy(\.isASCII) {
                    errors.append(.labelContainsOnlyASCIIAfterPunycodeDecode(label: newLabel))
                }
            }
        }

        verifyValidLabel(newLabel.unicodeScalars, errors: &errors)

        return newLabel.unicodeScalars
    }

    /// https://www.unicode.org/reports/tr46/#Validity_Criteria
    @usableFromInline
    func verifyValidLabel(_ label: Substring.UnicodeScalarView, errors: inout MappingErrors) {
        if !configuration.ignoreInvalidPunycode,
            !String(label).isInNFC
        {
            errors.append(.labelIsNotInNormalizationFormC(label: label))
        }

        switch configuration.checkHyphens {
        case true:
            if label.count > 3,
                label[label.index(label.startIndex, offsetBy: 2)]
                    == Unicode.Scalar.asciiHyphenMinus,
                label[label.index(label.startIndex, offsetBy: 3)] == Unicode.Scalar.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(
                        label: label
                    )
                )
            }
            if label.first == Unicode.Scalar.asciiHyphenMinus
                || label.last == Unicode.Scalar.asciiHyphenMinus
            {
                errors.append(
                    .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(
                        label: label
                    )
                )
            }
        case false:
            if !configuration.ignoreInvalidPunycode,
                label.hasIDNADomainNameMarkerPrefix
            {
                errors.append(
                    .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                        label: label
                    )
                )
            }
        }

        if !configuration.ignoreInvalidPunycode,
            label.first?.properties.generalCategory.isMark == true
        {
            errors.append(.labelStartsWithCombiningMark(label: label))
        }

        if !configuration.ignoreInvalidPunycode {
            for codePoint in label {
                switch IDNAMapping.for(scalar: codePoint) {
                case .valid, .deviation:
                    break
                case .mapped, .disallowed, .ignored:
                    errors.append(
                        .labelContainsInvalidUnicode(codePoint, label: label)
                    )
                }
            }
        }

        if configuration.useSTD3ASCIIRules {
            for codePoint in label where codePoint.isASCII {
                if !codePoint.isNumberOrLowercasedLetterOrHyphenMinusASCII {
                    errors.append(
                        .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                            label: label
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

    /// FIXME: Check this, just lowercasing everything?
    @usableFromInline
    func convertToLowercasedASCII(domainName: inout String) {
        if domainName.utf8.count < 16 {
            /// _SmallString path
            domainName = String(
                String.UnicodeScalarView(
                    domainName.unicodeScalars.map {
                        $0.toLowercasedASCIILetter()
                    }
                )
            )
        } else {
            domainName.withUTF8 { stringBuffer in
                let mutableStringBuffer = UnsafeMutableBufferPointer(mutating: stringBuffer)
                for idx in mutableStringBuffer.indices {
                    mutableStringBuffer[idx] = mutableStringBuffer[idx].toLowercasedASCIILetter()
                }
            }
        }
    }
}
