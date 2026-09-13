#!/usr/bin/env swift
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let testV2URL = "https://www.unicode.org/Public/idna/latest/IdnaTestV2.txt"
let outputPath = "Sources/CSwiftIDNATesting/src/cswift_idna_test_v2_cases.c"

struct CSwiftIDNATestV2CCase {
    let source: String
    let toUnicode: String?
    let toUnicodeStatus: [String]
    let toAsciiN: String?
    let toAsciiNStatus: [String]
}

func fetchWithRetries(url: URL) throws -> Data {
    let maxAttempts = 5
    for attempts in 1...maxAttempts {
        do {
            return try Data(contentsOf: url)
        } catch {
            if attempts == maxAttempts {
                throw error
            } else {
                print("✗ Failed to fetch latest release: \(String(reflecting: error))")
                print("Retrying in 3 seconds...")
                sleep(3)
            }
        }
    }
    fatalError("Unreachable")
}

/// Encodes a single octal byte escape (always 3 digits, so it can never merge with a
/// following hex/octal digit in the C string literal).
func octalByteEscape(_ byte: UInt8) -> String {
    let d0 = (byte >> 6) & 0x7
    let d1 = (byte >> 3) & 0x7
    let d2 = byte & 0x7
    return "\\\(d0)\(d1)\(d2)"
}

/// Returns the UTF-8 bytes of the given code point, or its WTF-8 bytes when it is a
/// surrogate (0xD800...0xDFFF), which has no valid UTF-8 encoding. Only handles the
/// BMP because IdnaTestV2.txt only ever escapes single BMP code points as `\uXXXX`.
func utf8OrWTF8Bytes(of codePoint: UInt32) -> [UInt8] {
    switch codePoint {
    case 0..<0x80:
        return [UInt8(codePoint)]
    case 0x80..<0x800:
        return [
            UInt8(0xC0 | (codePoint >> 6)),
            UInt8(0x80 | (codePoint & 0x3F)),
        ]
    default:
        return [
            UInt8(0xE0 | (codePoint >> 12)),
            UInt8(0x80 | ((codePoint >> 6) & 0x3F)),
            UInt8(0x80 | (codePoint & 0x3F)),
        ]
    }
}

/// C rejects `\u` universal character names for surrogates (0xD800...0xDFFF) and for code
/// points below 0x00A0. Every other `\uXXXX` compiles natively, so only these are rewritten.
func cRejectsUniversalCharacterName(for codePoint: UInt32) -> Bool {
    codePoint < 0xA0 || (0xD800...0xDFFF).contains(codePoint)
}

/// Rewrites only the literal `\uXXXX` escape sequences that C refuses to compile (see above)
/// into octal byte escapes of the UTF-8/WTF-8 encoding of the code point. All other characters
/// — including `\uXXXX` escapes C accepts — pass through unchanged so the diff stays minimal.
func escapedForCLiteral(_ string: String) -> String {
    let scalars = Array(string.unicodeScalars)
    var result = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
        if scalars[index] == "\\",
            index + 5 < scalars.count,
            scalars[index + 1] == "u",
            let codePoint = UInt32(
                String(String.UnicodeScalarView(scalars[(index + 2)...(index + 5)])),
                radix: 16
            )
        {
            if cRejectsUniversalCharacterName(for: codePoint) {
                for byte in utf8OrWTF8Bytes(of: codePoint) {
                    result.append(contentsOf: octalByteEscape(byte).unicodeScalars)
                }
            } else {
                result.append(contentsOf: scalars[index...(index + 5)])
            }
            index += 6
        } else {
            result.append(scalars[index])
            index += 1
        }
    }
    return String(result)
}

func parseStatusString(_ statusStr: String) -> [String] {
    let trimmed = statusStr.trimmingWhitespaces()
    if trimmed.isEmpty || trimmed == "[]" {
        return []
    }
    let content = String(trimmed.trimmingPrefix("[").dropLast())
    return content.split(separator: ",").map { $0.trimmingWhitespaces() }
}

func generate() -> String {
    let currentDirectory = FileManager.default.currentDirectoryPath
    guard currentDirectory.hasSuffix("swift-idna") else {
        fatalError(
            "This script must be run from the swift-idna root directory. Current directory: \(currentDirectory)."
        )
    }

    print("Downloading \(testV2URL) ...")
    let file = try! fetchWithRetries(url: URL(string: testV2URL)!)
    print("Downloaded \(file.count) bytes.")

    let utf8String = String(decoding: file, as: UTF8.self)

    var testCases: [CSwiftIDNATestV2CCase] = []
    for var line in utf8String.split(separator: "\n", omittingEmptySubsequences: false) {
        line = Substring(line.trimmingWhitespaces())
        if line.hasPrefix("#") { continue }
        if line.isEmpty { continue }
        if let commentIndex = line.lastIndex(of: "#") {
            line = Substring(String(line[..<commentIndex]).trimmingWhitespaces())
        }
        let parts = line.unicodeScalars.split(
            separator: ";",
            omittingEmptySubsequences: false
        ).map {
            String($0).trimmingWhitespaces()
        }
        guard parts.count == 7 else {
            fatalError("Invalid parts count: \(parts.debugDescription)")
        }
        let source = parts[0]
        let toUnicode = parts[1].emptyIfIsOnlyQuotesAndNilIfEmpty()
        let toUnicodeStatus = parseStatusString(parts[2])
        let toAsciiN = parts[3].emptyIfIsOnlyQuotesAndNilIfEmpty()
        let toAsciiNStatus = parseStatusString(parts[4])
        let testCase = CSwiftIDNATestV2CCase(
            source: source,
            toUnicode: toUnicode,
            toUnicodeStatus: toUnicodeStatus,
            toAsciiN: toAsciiN,
            toAsciiNStatus: toAsciiNStatus
        )
        testCases.append(testCase)
    }

    print("Parsed \(testCases.count) test cases, filtered to \(testCases.count) cases")

    var generatedCode = """
        #include "../include/CSwiftIDNATesting.h"
        #include <stddef.h>

        #define CSwift_IDNA_TEST_V2_CASES_COUNT \(testCases.count)

        extern const CSwiftIDNATestV2CCase cswift_idna_test_v2_cases[];

        const CSwiftIDNATestV2CCase* cswift_idna_test_v2_all_cases(size_t* count) {
            *count = CSwift_IDNA_TEST_V2_CASES_COUNT;
            return cswift_idna_test_v2_cases;
        }

        const CSwiftIDNATestV2CCase cswift_idna_test_v2_cases[] = {

        """

    for testCase in testCases {
        let toUnicodeStatusArray = testCase.toUnicodeStatus.map {
            "\"\($0)\""
        }.joined(separator: ", ")
        let toAsciiNStatusArray = testCase.toAsciiNStatus.map {
            "\"\($0)\""
        }.joined(separator: ", ")

        generatedCode += """
                    {
                        .source = "\(escapedForCLiteral(testCase.source))",
                        .toUnicode = \(testCase.toUnicode.quotedOrNULL()),
                        .toUnicodeStatus = (const char*[]){ \(toUnicodeStatusArray) },
                        .toUnicodeStatusCount = \(testCase.toUnicodeStatus.count),
                        .toAsciiN = \(testCase.toAsciiN.quotedOrNULL()),
                        .toAsciiNStatus = (const char*[]){ \(toAsciiNStatusArray) },
                        .toAsciiNStatusCount = \(testCase.toAsciiNStatus.count),
                    },

            """
    }

    generatedCode += """
        };

        """

    return generatedCode
}

extension StringProtocol {
    func trimmingWhitespaces() -> String {
        String(
            Substring.UnicodeScalarView(
                self.unicodeScalars
                    .drop(while: { $0.value == 32 })
                    .reversed()
                    .drop(while: { $0.value == 32 })
                    .reversed()
            )
        )
    }

    func emptyIfIsOnlyQuotesAndNilIfEmpty() -> String? {
        if self.isEmpty {
            return nil
        } else if self.unicodeScalars.count == 2,
            self.unicodeScalars.first == #"""#
                && self.unicodeScalars.last == #"""#
        {
            return ""
        } else {
            return String(self)
        }
    }
}

extension String? {
    func quotedOrNULL() -> String {
        switch self {
        case .some(let value):
            return "\"\(escapedForCLiteral(value))\""
        case .none:
            return "NULL"
        }
    }
}

let text = generate()
print("Generated \(text.split(whereSeparator: \.isNewline).count) lines")

if FileManager.default.fileExists(atPath: outputPath),
    try! String(contentsOfFile: outputPath, encoding: .utf8) == text
{
    print("Generated code matches current contents, no changes needed.")
} else {
    print("Writing to \(outputPath) ...")
    try! text.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

print("Done!")
