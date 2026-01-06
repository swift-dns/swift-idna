internal import _FoundationICU

// Mostly copy-pasted from https://github.com/apple/swift-foundation/blob/main/Sources/FoundationInternationalization/URLParser+ICU.swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#endif
#if FOUNDATION_FRAMEWORK
internal import Foundation_Private
#endif

package struct UIDNAHookICU {
    // `Sendable` notes: `UIDNA` from ICU is thread safe.
    struct UIDNAPointer: @unchecked Sendable {
        init(_ ptr: OpaquePointer?) { self.idnaTranscoder = ptr }
        var idnaTranscoder: OpaquePointer?
    }

    private static func U_SUCCESS(_ x: Int32) -> Bool {
        x <= U_ZERO_ERROR.rawValue
    }

    private static let idnaTranscoder: UIDNAPointer? = {
        var status = U_ZERO_ERROR
        let options = UInt32(
            UIDNA_CHECK_BIDI | UIDNA_CHECK_CONTEXTJ | UIDNA_NONTRANSITIONAL_TO_UNICODE
                | UIDNA_NONTRANSITIONAL_TO_ASCII
        )
        #if canImport(Darwin)
        let encoder = _FoundationICU.uidna_openUTS46(options, &status)
        #else
        let encoder = _FoundationICU.swift_uidna_openUTS46(options, &status)
        #endif
        guard U_SUCCESS(status.rawValue) else {
            return nil
        }
        return UIDNAPointer(encoder)
    }()

    private static func shouldAllow(_ errors: UInt32, encodeToASCII: Bool) -> Bool {
        let allowedErrors: UInt32
        if encodeToASCII {
            allowedErrors = 0
        } else {
            allowedErrors = UInt32(
                UIDNA_ERROR_EMPTY_LABEL | UIDNA_ERROR_LABEL_TOO_LONG
                    | UIDNA_ERROR_DOMAIN_NAME_TOO_LONG | UIDNA_ERROR_LEADING_HYPHEN
                    | UIDNA_ERROR_TRAILING_HYPHEN | UIDNA_ERROR_HYPHEN_3_4
            )
        }
        return errors & ~allowedErrors == 0
    }

    /// Type of `uidna_nameToASCII` and `uidna_nameToUnicode` functions
    private typealias TranscodingFunction<T> = (
        OpaquePointer?, UnsafePointer<T>?, Int32, UnsafeMutablePointer<T>?, Int32,
        UnsafeMutablePointer<UIDNAInfo>?, UnsafeMutablePointer<UErrorCode>?
    ) -> Int32

    private static func IDNACodedHost<T: FixedWidthInteger>(
        hostBuffer: UnsafeBufferPointer<T>,
        transcode: TranscodingFunction<T>,
        allowErrors: (UInt32) -> Bool,
        createString: (UnsafeMutablePointer<T>, Int) -> String?
    ) -> String? {
        let maxHostBufferLength = 2048
        if hostBuffer.count > maxHostBufferLength {
            return nil
        }

        guard let transcoder = idnaTranscoder else {
            return nil
        }

        let result: String? = withUnsafeTemporaryAllocation(
            of: T.self,
            capacity: maxHostBufferLength
        ) { outBuffer in
            var processingDetails = UIDNAInfo(
                size: Int16(MemoryLayout<UIDNAInfo>.size),
                isTransitionalDifferent: 0,
                reservedB3: 0,
                errors: 0,
                reservedI2: 0,
                reservedI3: 0
            )
            var error = U_ZERO_ERROR

            let hostBufferPtr = hostBuffer.baseAddress!
            let outBufferPtr = outBuffer.baseAddress!

            let charsConverted = transcode(
                transcoder.idnaTranscoder,
                hostBufferPtr,
                Int32(hostBuffer.count),
                outBufferPtr,
                Int32(outBuffer.count),
                &processingDetails,
                &error
            )

            if U_SUCCESS(error.rawValue), allowErrors(processingDetails.errors), charsConverted > 0
            {
                return createString(outBufferPtr, Int(charsConverted))
            }
            return nil
        }
        return result
    }

    private static func IDNACodedHostUTF8(
        _ utf8Buffer: UnsafeBufferPointer<UInt8>,
        encodeToASCII: Bool
    ) -> String? {
        var transcode: TranscodingFunction<CChar>
        #if canImport(Darwin)
        transcode = _FoundationICU.uidna_nameToUnicodeUTF8
        #else
        transcode = _FoundationICU.swift_uidna_nameToUnicodeUTF8
        #endif
        if encodeToASCII {
            #if canImport(Darwin)
            transcode = _FoundationICU.uidna_nameToASCII_UTF8
            #else
            transcode = _FoundationICU.swift_uidna_nameToASCII_UTF8
            #endif
        }
        return utf8Buffer.withMemoryRebound(to: CChar.self) { charBuffer in
            IDNACodedHost(
                hostBuffer: charBuffer,
                transcode: transcode,
                allowErrors: { errors in
                    shouldAllow(errors, encodeToASCII: encodeToASCII)
                },
                createString: { ptr, count in
                    let outBuffer = UnsafeBufferPointer(start: ptr, count: count).withMemoryRebound(
                        to: UInt8.self
                    ) { $0 }
                    var hostsAreEqual = false
                    if outBuffer.count == utf8Buffer.count {
                        hostsAreEqual = true
                        for i in 0..<outBuffer.count {
                            if utf8Buffer[i] == outBuffer[i] {
                                continue
                            }
                            guard utf8Buffer[i]._lowercased == outBuffer[i] else {
                                hostsAreEqual = false
                                break
                            }
                        }
                    }
                    if hostsAreEqual {
                        return String._tryFromUTF8(utf8Buffer)
                    } else {
                        return String._tryFromUTF8(outBuffer)
                    }
                }
            )
        }
    }

    private static func IDNACodedHostUTF16(
        _ utf16Buffer: UnsafeBufferPointer<UInt16>,
        encodeToASCII: Bool
    ) -> String? {
        var transcode: TranscodingFunction<UInt16>
        #if canImport(Darwin)
        transcode = _FoundationICU.uidna_nameToUnicode
        #else
        transcode = _FoundationICU.swift_uidna_nameToUnicode
        #endif
        if encodeToASCII {
            #if canImport(Darwin)
            transcode = _FoundationICU.uidna_nameToASCII
            #else
            transcode = _FoundationICU.swift_uidna_nameToASCII
            #endif
        }
        return IDNACodedHost(
            hostBuffer: utf16Buffer,
            transcode: transcode,
            allowErrors: { errors in
                shouldAllow(errors, encodeToASCII: encodeToASCII)
            },
            createString: { ptr, count in
                let outBuffer = UnsafeBufferPointer(start: ptr, count: count)
                var hostsAreEqual = false
                if outBuffer.count == utf16Buffer.count {
                    hostsAreEqual = true
                    for i in 0..<outBuffer.count {
                        if utf16Buffer[i] == outBuffer[i] {
                            continue
                        }
                        guard utf16Buffer[i] < 128,
                            UInt8(utf16Buffer[i])._lowercased == outBuffer[i]
                        else {
                            hostsAreEqual = false
                            break
                        }
                    }
                }
                if hostsAreEqual {
                    return String(_utf16: utf16Buffer)
                } else {
                    return String(_utf16: outBuffer)
                }
            }
        )
    }

    private static func IDNACodedHost(_ host: some StringProtocol, encodeToASCII: Bool) -> String? {
        let fastResult = host.utf8.withContiguousStorageIfAvailable {
            IDNACodedHostUTF8($0, encodeToASCII: encodeToASCII)
        }
        if let fastResult {
            return fastResult
        }
        #if FOUNDATION_FRAMEWORK
        if let fastCharacters = host._ns._fastCharacterContents() {
            let charsBuffer = UnsafeBufferPointer(start: fastCharacters, count: host._ns.length)
            return IDNACodedHostUTF16(charsBuffer, encodeToASCII: encodeToASCII)
        }
        #endif
        var hostString = String.init(host)
        return hostString.withUTF8 {
            IDNACodedHostUTF8($0, encodeToASCII: encodeToASCII)
        }
    }

    package static func encode(_ host: some StringProtocol) -> String? {
        IDNACodedHost(host, encodeToASCII: true)
    }

    package static func decode(_ host: some StringProtocol) -> String? {
        IDNACodedHost(host, encodeToASCII: false)
    }

}

extension UTF8.CodeUnit {
    // Copied from std; see comment in String.swift _uppercaseASCII() and _lowercaseASCII()
    var _lowercased: Self {
        let _uppercaseTable: UInt64 =
            0b0000_0000_0000_0000_0001_1111_1111_1111 &<< 32
        let isUpper = _uppercaseTable &>> UInt64(((self &- 1) & 0b0111_1111) &>> 1)
        let toAdd = (isUpper & 0x1) &<< 5
        return self &+ UInt8(truncatingIfNeeded: toAdd)
    }
}

extension String {
    init?(_utf16 input: UnsafeBufferPointer<UInt16>) {
        // Allocate input.count * 3 code points since one UTF16 code point may require up to three UTF8 code points when transcoded
        let str = withUnsafeTemporaryAllocation(of: UTF8.CodeUnit.self, capacity: input.count * 3) {
            contents in
            var count = 0
            let error = transcode(
                input.makeIterator(),
                from: UTF16.self,
                to: UTF8.self,
                stoppingOnError: true
            ) { codeUnit in
                contents[count] = codeUnit
                count += 1
            }

            guard !error else {
                return nil as String?
            }

            return String._tryFromUTF8(UnsafeBufferPointer(rebasing: contents[..<count]))
        }

        guard let str else {
            return nil
        }
        self = str
    }
}
