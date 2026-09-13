import CSwiftIDNATesting
import SwiftIDNA

/// Represents a single test case from the IDNA Test V2 specification:
/// https://www.unicode.org/Public/idna/16.0.0/IdnaTestV2.txt
struct IDNATestV2Case {
    /// Each of these statuses refer to some part of the Unicode document at
    /// https://www.unicode.org/reports/tr46 .
    /// This enum is named "Status" by the IDNAtestV2, but it's more like an "ErrorKind" enum.
    ///
    /// From https://www.unicode.org/Public/idna/16.0.0/IdnaTestV2.txt:
    /// ```text
    ///   Pn for Section 4 Processing step n
    ///   Vn for 4.1 Validity Criteria step n
    ///   U1 for UseSTD3ASCIIRules
    ///   An for 4.2 ToASCII step n
    ///   Bn for Bidi (in IDNA2008)
    ///   Cn for ContextJ (in IDNA2008)
    ///   Xn for toUnicode issues (see below)
    ///
    ///   ...
    ///
    ///   Implementations that allow values of particular input flags to be false would ignore
    ///   the corresponding status codes listed in the table below when testing for errors.
    ///
    ///   VerifyDnsLength:   A4_1, A4_2
    ///   CheckHyphens:      V2, V3
    ///   CheckJoiners:      Cn
    ///   CheckBidi:         Bn
    ///   UseSTD3ASCIIRules: U1
    /// ```
    ///
    /// For example, V4 refers to https://www.unicode.org/reports/tr46/#Validity_Criteria
    /// point number 4: If not CheckHyphens, the label must not begin with “xn--”.
    enum Status: String {
        case A3
        case A4_1, A4_2
        case B1, B2, B3, B4, B5, B6
        case C1, C2
        case V1, V2, V3, V4, V6, V7
        case U1
        case P4
        case X4_2
    }

    /// The source string to be tested
    let source: [UInt8]
    /// The result of applying toUnicode to the source, with Transitional_Processing=false
    let toUnicode: [UInt8]?
    /// A set of status codes for toUnicode operation
    let toUnicodeStatus: [Status]
    /// The result of applying toASCII to the source, with Transitional_Processing=false
    let toAsciiN: [UInt8]?
    /// A set of status codes for toAsciiN operation
    let toAsciiNStatus: [Status]

    init(
        source: [UInt8],
        toUnicode: [UInt8]?,
        toUnicodeStatus: [Status],
        toAsciiN: [UInt8]?,
        toAsciiNStatus: [Status]
    ) {
        self.source = source
        self.toUnicode = toUnicode
        self.toUnicodeStatus = toUnicodeStatus
        self.toAsciiN = toAsciiN
        self.toAsciiNStatus = toAsciiNStatus
    }

    init(from cCase: CSwiftIDNATestV2CCase) {
        self.source = unsafe Self.toUInt8Array(cCase.source)
        self.toUnicode = unsafe cCase.toUnicode.map { unsafe Self.toUInt8Array($0) }
        self.toAsciiN = unsafe cCase.toAsciiN.map { unsafe Self.toUInt8Array($0) }
        self.toUnicodeStatus = unsafe Array(
            UnsafeBufferPointer(
                start: cCase.toUnicodeStatus!,
                count: Int(cCase.toUnicodeStatusCount)
            )
        ).map {
            unsafe String(cString: $0!)
        }.map {
            Status(rawValue: $0)!
        }
        self.toAsciiNStatus = unsafe Array(
            UnsafeBufferPointer(
                start: cCase.toAsciiNStatus!,
                count: Int(cCase.toAsciiNStatusCount)
            )
        ).map {
            unsafe String(cString: $0!)
        }.map {
            Status(rawValue: $0)!
        }
    }

    private static func toUInt8Array(_ cString: UnsafePointer<CChar>) -> [UInt8] {
        let length = unsafe UTF8._nullCodeUnitOffset(in: cString)
        let buffer = unsafe UnsafeBufferPointer(start: cString, count: length)
        return unsafe buffer.withMemoryRebound(to: UInt8.self) {
            unsafe Array($0)
        }
    }

    private static var customCases: [IDNATestV2Case] {
        let massiveASCII = massivePunyCodeStrings.ascii
        let massiveUnicode = massivePunyCodeStrings.unicode
        let asciiString =
            "\(massiveASCII).\(massiveASCII).\(massiveASCII).\(massiveASCII).\(massiveASCII).\(massiveASCII)"
        let unicodeString =
            "\(massiveUnicode).\(massiveUnicode).\(massiveUnicode).\(massiveUnicode).\(massiveUnicode).\(massiveUnicode)"
        let customCases = [
            /// These cases are just for my peace of mind that the optimizations I've done and the pre-allocations will not
            /// result in a crash or something even for such massive ~invalid inputs.
            IDNATestV2Case(
                source: [UInt8](asciiString.utf8),
                toUnicode: [UInt8](unicodeString.utf8),
                toUnicodeStatus: [.P4, .P4, .P4, .P4, .P4, .P4],
                toAsciiN: [UInt8](asciiString.utf8),
                toAsciiNStatus: [.P4, .P4, .P4, .P4, .P4, .P4]
            ),
            IDNATestV2Case(
                source: [UInt8](unicodeString.utf8),
                toUnicode: [UInt8](unicodeString.utf8),
                toUnicodeStatus: [.A4_2],
                toAsciiN: [UInt8](asciiString.utf8),
                toAsciiNStatus: [.A4_2]
            ),
            /// This reproduces an impl issue that was caught in dev stage (before merge).
            IDNATestV2Case(
                source: [UInt8]("мойассистент.рф".utf8),
                toUnicode: [UInt8]("мойассистент.рф".utf8),
                toUnicodeStatus: [],
                toAsciiN: [UInt8]("xn--80akicokc0aablc.xn--p1ai".utf8),
                toAsciiNStatus: []
            ),
        ]
        return customCases
    }

    private static func allUnicodeCases() -> [IDNATestV2Case] {
        var count: Int = 0
        guard let ptr = unsafe cswift_idna_test_v2_all_cases(&count) else {
            fatalError("Failed to get IDNA Test V2 cases")
        }
        let all = (0..<count).map { i in unsafe IDNATestV2Case(from: ptr[i]) }
        return all
    }

    private static func allCases() -> [IDNATestV2Case] {
        Self.customCases + allUnicodeCases()
    }

    /// This is better for debuggability.
    /// If a certain case is failing, we'll know what index it belongs to so we can
    /// try to investigate that case alone.
    static func enumeratedAllCases() -> [(index: Int, case: IDNATestV2Case)] {
        Self.allCases().enumerated().map { ($0, $1) }
    }
}

extension IDNATestV2Case: CustomStringConvertible {
    var description: String {
        /// For the very few invalid-UTF8 cases, these string representation will be inaccurate
        /// as they'll be the repaired string's representation, not the original one.
        let sourceDebug = String(decoding: source, as: UTF8.self).debugDescription
        let toUnicodeDebug =
            toUnicode.map { String(decoding: $0, as: UTF8.self).debugDescription } ?? "nil"
        let toUnicodeStatusDebug = toUnicodeStatus.debugDescription
        let toAsciiNDebug =
            toAsciiN.map { String(decoding: $0, as: UTF8.self).debugDescription } ?? "nil"
        let toAsciiNStatusDebug = toAsciiNStatus.debugDescription
        return
            "IDNATestV2Case(source: \(sourceDebug), toUnicode: \(toUnicodeDebug), toUnicodeStatus: \(toUnicodeStatusDebug), toAsciiN: \(toAsciiNDebug), toAsciiNStatus: \(toAsciiNStatusDebug))"
    }
}

extension IDNATestV2Case.Status: CustomStringConvertible {
    var description: String {
        ".\(self.rawValue)"
    }
}

extension IDNA.MappingError {
    var correspondingIDNAStatus: IDNATestV2Case.Status? {
        switch self {
        case .labelStartsWithXNHyphenMinusHyphenMinusButContainsNonASCII:
            return .P4
        case .labelPunycodeEncodeFailed:
            return .A3
        case .labelPunycodeDecodeFailed:
            return .X4_2
        case .labelIsEmptyAfterPunycodeConversion:
            return .P4
        case .labelContainsOnlyASCIIAfterPunycodeDecode:
            return .P4
        case .trueVerifyDNSLengthArgumentRequiresLabelToBe63BytesOrLess:
            return .A4_2
        case .trueVerifyDNSLengthArgumentDisallowsEmptyLabel:
            return .A4_2
        case .trueVerifyDNSLengthArgumentDisallowsEmptyRootLabelWithTrailingDot:
            return .A4_2
        case .trueVerifyDNSLengthArgumentRequiresDomainNameToBe254BytesOrLess:
            return .A4_1
        case .trueVerifyDNSLengthArgumentDisallowsEmptyDomainName:
            return .A4_1
        case .labelIsNotInNormalizationFormC:
            return .V1
        case .trueCheckHyphensArgumentRequiresLabelToNotContainHyphenMinusAtPostion3and4:
            return .V2
        case .trueCheckHyphensArgumentRequiresLabelToNotStartOrEndWithHyphenMinus:
            return .V3
        case .falseCheckHyphensArgumentRequiresLabelToNotStartWithXNHyphenMinusHyphenMinus:
            return .V4
        case .labelStartsWithCombiningMark:
            return .V6
        case .labelContainsInvalidUnicode:
            return .V7
        case .trueUseSTD3ASCIIRulesArgumentRequiresLabelToOnlyContainCertainASCIICharacters:
            return .U1
        }
    }

    var disablingWillRequireIgnoringInvalidPunycode: Bool {
        switch self.correspondingIDNAStatus {
        case .none:
            return false
        case .some(let status):
            switch status {
            case .P4, .V1, .V4, .V6, .V7, .X4_2:
                return true
            case .A3, .A4_1, .A4_2, .B1, .B2, .B3, .B4, .B5, .B6, .C1, .C2, .V2, .V3, .U1:
                return false
            }
        }
    }

    /// Returns true if the error can be disabled, false otherwise.
    func disable(
        inConfiguration configuration: inout IDNA.Configuration,
        removingFrom statuses: inout [IDNATestV2Case.Status]
    ) -> Bool {
        guard let correspondingStatus = self.correspondingIDNAStatus else {
            return false
        }

        switch correspondingStatus {
        case .A3: break
        case .A4_1:
            configuration.verifyDNSLength = false
        case .A4_2:
            configuration.verifyDNSLength = false
        case .B1, .B2, .B3, .B4, .B5, .B6:
            configuration.checkBidi = false
        case .C1, .C2:
            configuration.checkJoiners = false
        case .P4:
            configuration.ignoreInvalidPunycode = true
            configuration.checkHyphens = false
        case .V1:
            configuration.ignoreInvalidPunycode = true
        case .V2:
            configuration.checkHyphens = false
        case .V3:
            configuration.checkHyphens = false
        case .V4:
            configuration.ignoreInvalidPunycode = true
        case .V6:
            configuration.ignoreInvalidPunycode = true
        case .V7:
            configuration.ignoreInvalidPunycode = true
        case .U1:
            configuration.useSTD3ASCIIRules = false
        case .X4_2:
            configuration.ignoreInvalidPunycode = true
        }

        statuses = statuses.filter { !$0.isRelated(to: correspondingStatus) }

        return true
    }
}

extension IDNATestV2Case.Status {
    func isRelated(to other: Self) -> Bool {
        self == other
            || (self == .P4 && other.isCheckHyphensStatus)
            || (other == .P4 && self.isCheckHyphensStatus)
    }
}

extension [IDNATestV2Case.Status] {
    func containsRelatedStatusCode(to statusCode: IDNATestV2Case.Status) -> Bool {
        self.contains { $0.isRelated(to: statusCode) }
    }
}

extension IDNATestV2Case.Status {
    var isCheckHyphensStatus: Bool {
        switch self {
        case .V1, .V2, .V3, .V4, .V6, .V7:
            return true
        default:
            return false
        }
    }
}

private let massivePunyCodeStrings: (ascii: String, unicode: String) = (
    "xn--aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-rj4941efkahmhmhmhmhmhm089521hgkaimimimimimim",
    "aaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa點看aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)
