#!/usr/bin/env swift
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `blockShift` is log2 of the trie block size. Must match CSWIFT_IDNA_MARK_BLOCK_SHIFT in
/// CSwiftIDNA.h.
let blockShift = 8
/// Code points at or above this limit carry no General_Category=Mark data, except for the one
/// range this script verifies below. Must match CSWIFT_IDNA_MARK_TRIE_LIMIT in CSwiftIDNA.h.
let trieLimit: UInt32 = 0x30000
/// The only General_Category=Mark range at or above the trie limit, which the runtime answers
/// arithmetically instead of storing 800 KB of empty trie for it. If a future Unicode version
/// adds another one, this script fatalErrors, and both these constants and the CSwiftIDNA.h
/// macros must be updated together.
let tailStart: UInt32 = 0xE0100
let tailEnd: UInt32 = 0xE01EF

let derivedGeneralCategoryURL =
    "https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedGeneralCategory.txt"
let outputPath = "Sources/CSwiftIDNA/src/cswift_idna_mark_table.c"

let maxCodePoint: UInt32 = 0x10FFFF
let blockSize = 1 << blockShift
let blockMask = UInt32(blockSize - 1)
let wordsPerBlock = blockSize / 64

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

/// Parses the `Mn`, `Mc` and `Me` general categories, which together are `General_Category=Mark`.
/// [UAX #44, General_Category Values](https://www.unicode.org/reports/tr44/#General_Category_Values)
func parse(_ text: String) -> [Bool] {
    var isMark = [Bool](repeating: false, count: Int(maxCodePoint) + 1)

    for rawLine in text.split(separator: "\n") {
        var line = rawLine
        if let hash = line.firstIndex(of: "#") {
            line = line[..<hash]
        }
        line = Substring(line.trimmingCharacters(in: .whitespaces))
        if line.isEmpty { continue }

        let fields = line.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2 else {
            fatalError(
                "DerivedGeneralCategory line has less than 2 fields: \(line.debugDescription)"
            )
        }

        let category = fields[1].trimmingCharacters(in: .whitespaces)
        guard category == "Mn" || category == "Mc" || category == "Me" else { continue }

        let range = fields[0].trimmingCharacters(in: .whitespaces)
        let bounds = range.components(separatedBy: "..")
        let first = UInt32(bounds[0], radix: 16)!
        let last = bounds.count == 2 ? UInt32(bounds[1], radix: 16)! : first
        for codePoint in first...last {
            isMark[Int(codePoint)] = true
        }
    }

    return isMark
}

struct BuiltTables {
    var blockOffsets: [UInt16] = []
    var bits: [UInt64] = []
}

/// Packs the mark bits into 64-bit words and interns identical blocks, the same two-stage shape
/// the mapping and normalization tries use.
func build(_ isMark: [Bool]) -> BuiltTables {
    var tables = BuiltTables()
    var offsetForBlock: [[UInt64]: Int] = [:]

    let numBlocks = Int(trieLimit) / blockSize
    precondition(numBlocks * blockSize == Int(trieLimit), "trie limit not a block multiple")

    for blockIndex in 0..<numBlocks {
        var block = [UInt64](repeating: 0, count: wordsPerBlock)
        for offset in 0..<blockSize {
            let codePoint = blockIndex * blockSize + offset
            if isMark[codePoint] {
                block[offset / 64] |= 1 << UInt64(offset % 64)
            }
        }

        if let existing = offsetForBlock[block] {
            tables.blockOffsets.append(UInt16(existing))
            continue
        }

        let offset = tables.bits.count
        precondition(offset < (1 << 16), "mark bits offset exceeds 16 bits")
        offsetForBlock[block] = offset
        tables.blockOffsets.append(UInt16(offset))
        tables.bits.append(contentsOf: block)
    }

    return tables
}

func decode(_ codePoint: UInt32, _ tables: BuiltTables) -> Bool {
    if codePoint >= trieLimit {
        return codePoint >= tailStart && codePoint <= tailEnd
    }
    let blockOffset = Int(tables.blockOffsets[Int(codePoint) >> blockShift])
    let word = tables.bits[blockOffset + Int((codePoint & blockMask) >> 6)]
    return (word >> (codePoint & 63)) & 1 == 1
}

func verify(_ isMark: [Bool], _ tables: BuiltTables) {
    for codePoint in 0...maxCodePoint {
        let decoded = decode(codePoint, tables)
        guard decoded == isMark[Int(codePoint)] else {
            fatalError(
                "Round-trip mismatch at U+\(String(codePoint, radix: 16, uppercase: true)): "
                    + "expected \(isMark[Int(codePoint)]), got \(decoded)"
            )
        }
    }
    print("Round-trip verification passed for \(maxCodePoint + 1) code points.")
}

/// Asserts the data property the runtime relies on, so that a future Unicode version that breaks
/// it turns into a loud generator failure instead of silent misbehavior.
func verifyRuntimeAssumptions(_ isMark: [Bool]) {
    for codePoint in trieLimit...maxCodePoint where isMark[Int(codePoint)] {
        precondition(
            codePoint >= tailStart && codePoint <= tailEnd,
            "General_Category=Mark code point above the trie limit and outside the known tail "
                + "range at U+\(String(codePoint, radix: 16, uppercase: true))"
        )
    }
    for codePoint in tailStart...tailEnd {
        precondition(
            isMark[Int(codePoint)],
            "Tail range is no longer entirely General_Category=Mark at "
                + "U+\(String(codePoint, radix: 16, uppercase: true))"
        )
    }
    print(
        "Runtime assumptions verified: the only marks at or above the trie limit are "
            + "U+\(String(tailStart, radix: 16, uppercase: true))..."
            + "U+\(String(tailEnd, radix: 16, uppercase: true))"
    )
}

/// Emits a `const <cType> <name>[] = { ... }` C array. Integer literals are coerced to the array
/// element type, so no unsigned suffix is needed.
func emitArray(
    _ cType: String,
    _ name: String,
    _ values: [some FixedWidthInteger],
    perLine: Int = 16,
    into code: inout String
) {
    code += "const \(cType) \(name)[\(values.count)] = {\n"
    for start in stride(from: 0, to: values.count, by: perLine) {
        let end = min(start + perLine, values.count)
        let line = values[start..<end].map { "0x" + String($0, radix: 16, uppercase: true) }
            .joined(separator: ", ")
        code += "    \(line),\n"
    }
    code += "};\n\n"
}

func emit(_ tables: BuiltTables) -> String {
    var code = """
        // This file is generated by the utils/MarkTableGenerator.swift script.

        #include "../include/CSwiftIDNA.h"
        #include <stdint.h>

        """

    emitArray("uint16_t", "cswift_idna_mark_block_offsets", tables.blockOffsets, into: &code)
    emitArray("uint64_t", "cswift_idna_mark_bits", tables.bits, perLine: 8, into: &code)

    return code
}

func run() {
    let currentDirectory = FileManager.default.currentDirectoryPath
    guard currentDirectory.hasSuffix("swift-idna") else {
        fatalError(
            "This script must be run from the swift-idna root directory. "
                + "Current directory: \(currentDirectory)."
        )
    }

    print("Downloading \(derivedGeneralCategoryURL) ...")
    let file = try! fetchWithRetries(url: URL(string: derivedGeneralCategoryURL)!)
    print("Downloaded \(file.count) bytes")

    let text = String(decoding: file, as: UTF8.self)
    let isMark = parse(text)
    print("Parsed \(isMark.lazy.filter { $0 }.count) General_Category=Mark code points")

    verifyRuntimeAssumptions(isMark)

    let tables = build(isMark)
    print(
        "Built: blockOffsets=\(tables.blockOffsets.count) bits=\(tables.bits.count) "
            + "(shift=\(blockShift))"
    )
    let totalBytes = tables.blockOffsets.count * 2 + tables.bits.count * 8
    let totalKB = String(format: "%.1f", Double(totalBytes) / 1024)
    print("Total table bytes: \(totalBytes) (\(totalKB) KB)")

    verify(isMark, tables)

    let generated = emit(tables)
    print("Generated \(generated.split(whereSeparator: \.isNewline).count) lines")

    if FileManager.default.fileExists(atPath: outputPath),
        try! String(contentsOfFile: outputPath, encoding: .utf8) == generated
    {
        print("Generated code matches current contents, no changes needed.")
    } else {
        print("Writing to \(outputPath) ...")
        try! generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    print("Done!")
}

run()
