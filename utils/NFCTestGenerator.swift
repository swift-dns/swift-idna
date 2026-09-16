#!/usr/bin/env swift
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let normalizationTestURL = "https://www.unicode.org/Public/UCD/latest/ucd/NormalizationTest.txt"
let outputPath = "Sources/CSwiftIDNATesting/src/cswift_idna_nfc_test_cases.c"

struct CSwiftIDNANFCTestCCase {
    let columns: [[UInt8]]
    let part: Int
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

func utf8Bytes(_ scalars: [UInt32]) -> [UInt8] {
    var out: [UInt8] = []
    for scalar in scalars {
        guard let unicodeScalar = Unicode.Scalar(scalar) else {
            fatalError("Invalid scalar U+\(String(scalar, radix: 16, uppercase: true))")
        }
        out.append(contentsOf: Array(unicodeScalar.utf8))
    }
    return out
}

func parseScalars(_ s: Substring) -> [UInt32] {
    s.split(separator: " ").map {
        UInt32($0, radix: 16)!
    }
}

func generate() -> String {
    let currentDirectory = FileManager.default.currentDirectoryPath
    guard currentDirectory.hasSuffix("swift-idna") else {
        fatalError(
            "This script must be run from the swift-idna root directory. Current directory: \(currentDirectory)."
        )
    }

    print("Downloading \(normalizationTestURL) ...")
    let file = try! fetchWithRetries(url: URL(string: normalizationTestURL)!)
    print("Downloaded \(file.count) bytes.")

    let utf8String = String(decoding: file, as: UTF8.self)

    var testCases: [CSwiftIDNANFCTestCCase] = []
    var currentPart = -1
    var seenParts: Set<Int> = []
    for var line in utf8String.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("@Part") {
            currentPart = Int(line.dropFirst(5).prefix(1))!
            seenParts.insert(currentPart)
            continue
        }
        if let hash = line.firstIndex(of: "#") {
            line = line[..<hash]
        }
        if line.isEmpty { continue }

        let parts = line.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 5 else {
            fatalError("Line has less than 5 columns: \(line.debugDescription)")
        }
        guard currentPart >= 0 else {
            fatalError("Test case before the first @Part marker: \(line.debugDescription)")
        }

        let columns = (0..<5).map { utf8Bytes(parseScalars(parts[$0])) }
        if currentPart == 1 {
            guard parseScalars(parts[0]).count == 1 else {
                fatalError("Part1 case with a multi-scalar first column: \(line.debugDescription)")
            }
        }
        testCases.append(CSwiftIDNANFCTestCCase(columns: columns, part: currentPart))
    }

    guard seenParts.sorted() == Array(0..<seenParts.count), seenParts.count >= 4 else {
        fatalError(
            "Expected contiguous parts starting at 0 covering at least 0...3, saw \(seenParts.sorted())"
        )
    }

    print("Parsed \(testCases.count) test cases across parts \(seenParts.sorted())")

    var generatedCode = """
        #include "../include/CSwiftIDNATesting.h"
        #include <stddef.h>

        #define CSwift_IDNA_NFC_TEST_CASES_COUNT \(testCases.count)

        extern const CSwiftIDNANFCTestCCase cswift_idna_nfc_test_cases[];

        const CSwiftIDNANFCTestCCase* cswift_idna_nfc_test_all_cases(size_t* count) {
            *count = CSwift_IDNA_NFC_TEST_CASES_COUNT;
            return cswift_idna_nfc_test_cases;
        }

        const CSwiftIDNANFCTestCCase cswift_idna_nfc_test_cases[] = {

        """

    for testCase in testCases {
        let literals = testCase.columns.map { column in
            "\"" + column.map { octalByteEscape($0) }.joined() + "\""
        }
        generatedCode += """
                {
                    .c1 = \(literals[0]),
                    .c1Count = \(testCase.columns[0].count),
                    .c2 = \(literals[1]),
                    .c2Count = \(testCase.columns[1].count),
                    .c3 = \(literals[2]),
                    .c3Count = \(testCase.columns[2].count),
                    .c4 = \(literals[3]),
                    .c4Count = \(testCase.columns[3].count),
                    .c5 = \(literals[4]),
                    .c5Count = \(testCase.columns[4].count),
                    .part = \(testCase.part),
                },

            """
    }

    generatedCode += """
        };

        """

    return generatedCode
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
