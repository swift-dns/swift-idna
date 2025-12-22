@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNA {
    public struct CollectedMappingErrors: Error {
        public let domainName: String
        public let errors: [MappingError]

        @inlinable
        init(domainName: String, errors: [MappingError]) {
            self.domainName = domainName
            self.errors = errors
        }
    }

    @usableFromInline
    struct MappingErrors: ~Escapable {
        @usableFromInline
        let domainNameSpan: Span<UInt8>
        @usableFromInline
        var errors: [MappingError]?

        @inlinable
        var isEmpty: Bool {
            self.errors?.isEmpty ?? true
        }

        @inlinable
        @_lifetime(copy domainNameSpan)
        init(domainNameSpan: Span<UInt8>) {
            self.domainNameSpan = domainNameSpan
            self.errors = nil
        }

        @inlinable
        @_lifetime(&self)
        mutating func append(_ error: MappingError) {
            if self.errors == nil {
                self.errors = [error]
            } else {
                self.errors!.append(error)
            }
        }

        @inlinable
        func collect() -> CollectedMappingErrors? {
            guard
                let errors = self.errors,
                !errors.isEmpty
            else {
                return nil
            }
            return CollectedMappingErrors(
                domainName: String(_uncheckedAssumingValidUTF8: self.domainNameSpan),
                errors: errors
            )
        }
    }

    @nonexhaustive
    public enum MappingError: Sendable, CustomStringConvertible {
        case labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(label: String)
        case labelPunycodeEncodeFailed(label: [UInt8])
        case labelPunycodeDecodeFailed(label: String)
        case labelIsEmptyAfterPunycodeConversion(label: String)
        case labelContainsOnlyASCIIAfterPunycodeDecode(label: String)
        case trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(
            length: Int,
            labels: [UInt8]
        )
        case trueVerifyDNSLengthArgumentDisallowsEmptyLabel(labels: [UInt8])
        case trueVerifyDNSLengthArgumentDisallowsEmptyRootLabelWithTrailingDot(
            labels: [UInt8]
        )
        case trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
            length: Int,
            labels: [UInt8]
        )
        case trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(labels: [UInt8])
        case labelIsNotInNormalizationFormC(label: String)
        case trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(
            label: String
        )
        case trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(label: String)
        case falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
            label: String
        )
        case labelStartsWithCombiningMark(label: String)
        case labelContainsInvalidUnicode(Unicode.Scalar, label: String)
        case trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
            label: String
        )

        public var description: String {
            switch self {
            case .labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(let label):
                return
                    ".labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII(\(label.debugDescription))"
            case .labelPunycodeEncodeFailed(let label):
                return
                    ".labelPunycodeEncodeFailed(\(label.debugDescription))"
            case .labelPunycodeDecodeFailed(let label):
                return
                    ".labelPunycodeDecodeFailed(\(label.debugDescription))"
            case .labelIsEmptyAfterPunycodeConversion(let label):
                return
                    ".labelIsEmptyAfterPunycodeConversion(\(label.debugDescription))"
            case .labelContainsOnlyASCIIAfterPunycodeDecode(let label):
                return
                    ".labelContainsOnlyASCIIAfterPunycodeDecode(\(label.debugDescription))"
            case .trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(
                let length,
                let label
            ):
                return
                    ".trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess(length: \(length), label: \(label.debugDescription))"
            case .trueVerifyDNSLengthArgumentDisallowsEmptyLabel(let label):
                return
                    ".trueVerifyDNSLengthArgumentDisallowsEmptyLabel(\(label.debugDescription))"
            case .trueVerifyDNSLengthArgumentDisallowsEmptyRootLabelWithTrailingDot(let labels):
                return
                    ".trueVerifyDNSLengthArgumentDisallowsEmptyRootLabelWithTrailingDot(labels: \(labels.debugDescription))"
            case .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(
                let length,
                let labels
            ):
                return
                    ".trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess(length: \(length), labels: \(labels.debugDescription))"
            case .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(let labels):
                return
                    ".trueVerifyDNSLengthArgumentDisallowsEmptyDomainName(\(labels.debugDescription))"
            case .labelIsNotInNormalizationFormC(let label):
                return
                    ".labelIsNotInNormalizationFormC(\(label.debugDescription))"
            case .trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(
                let label
            ):
                return
                    ".trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4(\(label.debugDescription))"
            case .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(let label):
                return
                    ".trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus(\(label.debugDescription))"
            case .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(
                let label
            ):
                return
                    ".falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus(\(label.debugDescription))"
            case .labelStartsWithCombiningMark(let label):
                return
                    ".labelStartsWithCombiningMark(\(label.debugDescription))"
            case .labelContainsInvalidUnicode(let codePoint, let label):
                return
                    ".labelContainsInvalidUnicode(\(codePoint.debugDescription), label: \(label.debugDescription))"
            case .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(
                let label
            ):
                return
                    ".trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters(\(label.debugDescription))"
            }
        }
    }
}
