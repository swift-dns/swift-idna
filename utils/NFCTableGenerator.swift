#!/usr/bin/env swift
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `blockShift` is log2 of the trie block size. Must match CSWIFT_IDNA_NFC_BLOCK_SHIFT in CSwiftIDNA.h.
let blockShift = 6
/// Code points at or above this limit are not covered by the trie and are all inert.
/// Must match CSWIFT_IDNA_NFC_TRIE_LIMIT in CSwiftIDNA.h.
/// If a future Unicode version assigns normalization-relevant data above this limit, this script
/// fatalErrors, and both this constant and the CSwiftIDNA.h macro must be bumped together.
let trieLimit: UInt32 = 0x30000

let unicodeDataURL = "https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt"
let derivedNormalizationPropsURL =
    "https://www.unicode.org/Public/UCD/latest/ucd/DerivedNormalizationProps.txt"
let outputPath = "Sources/CSwiftIDNA/src/cswift_idna_nfc_table.c"

let maxCodePoint: UInt32 = 0x10FFFF
let blockSize = 1 << blockShift
let blockMask = blockSize - 1

let hangulSyllableBase: UInt32 = 0xAC00
let hangulSyllableEnd: UInt32 = 0xD7A3

/// Trie value tags. Must match the `Tag` enum in Sources/SwiftIDNA/NFCNormalization.swift, which
/// decodes the values this script bakes into the table.
enum Tag: UInt16 {
    case inert = 0
    case cccOnly = 1
    case maybe = 2
    case maybeWithDecomposition = 3
    case decompositionQCYes = 4
    case decompositionQCNo = 5
    case hangulSyllable = 6
}

enum QuickCheck: Equatable {
    case yes
    case no
    case maybe
}

struct ScalarNormData: Equatable {
    var ccc: UInt8 = 0
    var quickCheck: QuickCheck = .yes
    /// The fully-recursively-expanded, canonically-ordered NFD expansion, as (scalar, ccc) pairs.
    /// Empty when the scalar does not have a canonical decomposition.
    var nfd: [(UInt32, UInt8)] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ccc == rhs.ccc
            && lhs.quickCheck == rhs.quickCheck
            && lhs.nfd.elementsEqual(rhs.nfd, by: ==)
    }
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

func parseScalars(_ s: Substring) -> [UInt32] {
    s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map {
        UInt32($0, radix: 16)!
    }
}

/// Parses the code-point-or-range first column of a UCD data file line.
func parseCodePointRange(_ s: Substring) -> ClosedRange<UInt32> {
    let bounds = s.split(separator: "..")
    let start = UInt32(bounds[0], radix: 16)!
    let end = bounds.count == 2 ? UInt32(bounds[1], radix: 16)! : start
    return start...end
}

struct ParsedUCD {
    var ccc = [UInt8](repeating: 0, count: Int(maxCodePoint) + 1)
    var canonicalDecompositions: [UInt32: [UInt32]] = [:]
    var quickChecks = [QuickCheck](repeating: .yes, count: Int(maxCodePoint) + 1)
    var fullCompositionExclusions: Set<UInt32> = []
}

func parseUnicodeData(_ text: String, into ucd: inout ParsedUCD) {
    var pendingRangeFirst: UInt32? = nil

    for line in text.split(separator: "\n") {
        if line.isEmpty { continue }

        let fields = line.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 6 else {
            fatalError("UnicodeData line has less than 6 fields: \(line.debugDescription)")
        }

        let codePoint = UInt32(fields[0], radix: 16)!
        let name = fields[1]
        let ccc = UInt8(fields[3])!
        let decomposition = fields[5]

        if name.hasSuffix(", First>") {
            guard pendingRangeFirst == nil else {
                fatalError("Nested First range at \(line.debugDescription)")
            }
            guard ccc == 0, decomposition.isEmpty else {
                fatalError("First range with normalization data at \(line.debugDescription)")
            }
            pendingRangeFirst = codePoint
            continue
        }
        if name.hasSuffix(", Last>") {
            guard let first = pendingRangeFirst else {
                fatalError("Last range without First at \(line.debugDescription)")
            }
            guard ccc == 0, decomposition.isEmpty else {
                fatalError("Last range with normalization data at \(line.debugDescription)")
            }
            if name.hasPrefix("<Hangul Syllable") {
                guard first == hangulSyllableBase, codePoint == hangulSyllableEnd else {
                    fatalError("Unexpected Hangul Syllable range \(first)...\(codePoint)")
                }
            }
            pendingRangeFirst = nil
            continue
        }

        ucd.ccc[Int(codePoint)] = ccc

        if !decomposition.isEmpty, !decomposition.hasPrefix("<") {
            ucd.canonicalDecompositions[codePoint] = parseScalars(decomposition)
        }
    }

    guard pendingRangeFirst == nil else {
        fatalError("Unterminated First range")
    }
}

func parseDerivedNormalizationProps(_ text: String, into ucd: inout ParsedUCD) {
    for rawLine in text.split(separator: "\n") {
        var line = rawLine
        if let hash = line.firstIndex(of: "#") {
            line = line[..<hash]
        }
        line = Substring(line.trimmingCharacters(in: .whitespaces))
        if line.isEmpty { continue }

        let parts = line.split(separator: ";", omittingEmptySubsequences: false).map {
            Substring($0.trimmingCharacters(in: .whitespaces))
        }

        switch parts.count >= 2 ? parts[1] : "" {
        case "Full_Composition_Exclusion":
            for codePoint in parseCodePointRange(parts[0]) {
                ucd.fullCompositionExclusions.insert(codePoint)
            }
        case "NFC_QC":
            guard parts.count >= 3 else {
                fatalError("NFC_QC line has less than 3 parts: \(line.debugDescription)")
            }
            let quickCheck: QuickCheck
            switch parts[2] {
            case "N": quickCheck = .no
            case "M": quickCheck = .maybe
            default: fatalError("Unexpected NFC_QC value: \(line.debugDescription)")
            }
            for codePoint in parseCodePointRange(parts[0]) {
                ucd.quickChecks[Int(codePoint)] = quickCheck
            }
        default:
            continue
        }
    }
}

/// Recursively expands the canonical decomposition of a scalar, then applies the
/// Canonical Ordering Algorithm, producing the exact NFD expansion of the lone scalar.
func fullNFD(_ codePoint: UInt32, _ ucd: ParsedUCD) -> [(UInt32, UInt8)] {
    var expanded: [UInt32] = []
    var stack: [UInt32] = [codePoint]
    while let scalar = stack.popLast() {
        if let decomposition = ucd.canonicalDecompositions[scalar] {
            stack.append(contentsOf: decomposition.reversed())
        } else {
            expanded.append(scalar)
        }
    }

    var result = expanded.map { ($0, ucd.ccc[Int($0)]) }
    /// Canonical Ordering Algorithm: a stable sort of nonzero-ccc sequences by ccc.
    var index = 1
    while index < result.count {
        let ccc = result[index].1
        if ccc != 0 {
            var target = index
            while target > 0, result[target - 1].1 > ccc {
                target -= 1
            }
            if target != index {
                let element = result.remove(at: index)
                result.insert(element, at: target)
            }
        }
        index += 1
    }
    return result
}

func computeNormData(_ ucd: ParsedUCD) -> [ScalarNormData] {
    var normData = [ScalarNormData](repeating: ScalarNormData(), count: Int(maxCodePoint) + 1)
    for codePoint in 0...maxCodePoint {
        var data = ScalarNormData()
        data.ccc = ucd.ccc[Int(codePoint)]
        data.quickCheck = ucd.quickChecks[Int(codePoint)]
        if ucd.canonicalDecompositions[codePoint] != nil {
            data.nfd = fullNFD(codePoint, ucd)
        }
        normData[Int(codePoint)] = data
    }
    return normData
}

struct CompositionPair {
    var first: UInt32
    var second: UInt32
    var composite: UInt32
}

func computeCompositionPairs(_ ucd: ParsedUCD) -> [CompositionPair] {
    var pairs: [CompositionPair] = []
    for (composite, decomposition) in ucd.canonicalDecompositions {
        guard decomposition.count == 2 else {
            precondition(
                decomposition.count == 1,
                "Canonical decomposition of unexpected length \(decomposition.count) "
                    + "at U+\(String(composite, radix: 16, uppercase: true))"
            )
            continue
        }
        if ucd.fullCompositionExclusions.contains(composite) {
            continue
        }
        pairs.append(
            CompositionPair(
                first: decomposition[0],
                second: decomposition[1],
                composite: composite
            )
        )
    }
    pairs.sort {
        ($0.first, $0.second) < ($1.first, $1.second)
    }
    return pairs
}

func findSubsequence(_ haystack: [UInt32], _ needle: [UInt32]) -> Int? {
    if needle.isEmpty { return 0 }
    if needle.count > haystack.count { return nil }
    for start in 0...(haystack.count - needle.count) {
        var matches = true
        for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
            matches = false
            break
        }
        if matches { return start }
    }
    return nil
}

struct BuiltTables {
    var blockOffsets: [UInt16] = []
    var packedValues: [UInt16] = []
    var decompositionSlices: [UInt32] = []
    var decompositionScalars: [UInt32] = []
    var compositionPairs: [UInt64] = []
}

func packDecompositionScalar(_ scalar: UInt32, _ ccc: UInt8) -> UInt32 {
    precondition(scalar < (1 << 21), "decomposition scalar exceeds 21 bits")
    return (UInt32(ccc) << 21) | scalar
}

func build(_ normData: [ScalarNormData], _ pairs: [CompositionPair]) -> BuiltTables {
    var tables = BuiltTables()

    var sliceIndexForNFD: [[UInt32]: Int] = [:]

    /// Interns an NFD expansion into the decomposition scalars blob (sharing subsequences) and
    /// returns the index into `decompositionSlices`.
    func internNFD(_ nfd: [(UInt32, UInt8)]) -> Int {
        let packed = nfd.map { packDecompositionScalar($0.0, $0.1) }
        if let existing = sliceIndexForNFD[packed] {
            return existing
        }
        let offset: Int
        if let shared = findSubsequence(tables.decompositionScalars, packed) {
            offset = shared
        } else {
            offset = tables.decompositionScalars.count
            tables.decompositionScalars.append(contentsOf: packed)
        }
        precondition(offset < (1 << 24), "decomposition offset exceeds 24 bits")
        precondition(packed.count < (1 << 8), "decomposition length exceeds 8 bits")
        let sliceIndex = tables.decompositionSlices.count
        tables.decompositionSlices.append(UInt32(offset << 8) | UInt32(packed.count))
        sliceIndexForNFD[packed] = sliceIndex
        return sliceIndex
    }

    func value(for codePoint: UInt32, _ data: ScalarNormData) -> UInt16 {
        if codePoint >= hangulSyllableBase, codePoint <= hangulSyllableEnd {
            precondition(
                data.ccc == 0 && data.quickCheck == .yes && data.nfd.isEmpty,
                "Hangul syllable with unexpected normalization data"
            )
            return Tag.hangulSyllable.rawValue << 13
        }

        if data.nfd.isEmpty {
            switch data.quickCheck {
            case .yes:
                if data.ccc == 0 {
                    return Tag.inert.rawValue << 13
                }
                return (Tag.cccOnly.rawValue << 13) | UInt16(data.ccc)
            case .maybe:
                return (Tag.maybe.rawValue << 13) | UInt16(data.ccc)
            case .no:
                fatalError(
                    "NFC_QC=No scalar without a canonical decomposition at "
                        + "U+\(String(codePoint, radix: 16, uppercase: true))"
                )
            }
        }

        let index = internNFD(data.nfd)
        precondition(index < (1 << 13), "decomposition slice index exceeds 13 bits")
        switch data.quickCheck {
        case .yes:
            precondition(data.ccc == 0, "NFC_QC=Yes decomposable scalar with nonzero ccc")
            return (Tag.decompositionQCYes.rawValue << 13) | UInt16(index)
        case .maybe:
            precondition(data.ccc == 0, "NFC_QC=Maybe decomposable scalar with nonzero ccc")
            return (Tag.maybeWithDecomposition.rawValue << 13) | UInt16(index)
        case .no:
            return (Tag.decompositionQCNo.rawValue << 13) | UInt16(index)
        }
    }

    var values = [UInt16](repeating: 0, count: Int(trieLimit))
    for codePoint in 0..<trieLimit {
        values[Int(codePoint)] = value(for: codePoint, normData[Int(codePoint)])
    }

    let numBlocks = Int(trieLimit) / blockSize
    precondition(numBlocks * blockSize == Int(trieLimit), "trie limit not a block multiple")

    var offsetForBlock: [ArraySlice<UInt16>: Int] = [:]
    for blockIndex in 0..<numBlocks {
        let lower = blockIndex * blockSize
        let upper = lower + blockSize
        let block = values[lower..<upper]

        if let existing = offsetForBlock[block] {
            tables.blockOffsets.append(UInt16(existing))
            continue
        }

        var overlap = min(tables.packedValues.count, blockSize - 1)
        while overlap > 0 {
            var matches = true
            let base = tables.packedValues.count - overlap
            for offset in 0..<overlap {
                if tables.packedValues[base + offset] != block[block.startIndex + offset] {
                    matches = false
                    break
                }
            }
            if matches { break }
            overlap -= 1
        }

        let offset = tables.packedValues.count - overlap
        for position in overlap..<blockSize {
            tables.packedValues.append(block[block.startIndex + position])
        }
        precondition(offset < (1 << 16), "packedValues offset exceeds uint16")
        tables.blockOffsets.append(UInt16(offset))
        offsetForBlock[block] = offset
    }

    precondition(tables.packedValues.count < (1 << 16), "packedValues exceeds uint16 index space")

    for pair in pairs {
        precondition(pair.first < (1 << 21), "composition pair first exceeds 21 bits")
        precondition(pair.second < (1 << 21), "composition pair second exceeds 21 bits")
        precondition(pair.composite < (1 << 22), "composition pair composite exceeds 22 bits")
        tables.compositionPairs.append(
            (UInt64(pair.first) << 43) | (UInt64(pair.second) << 22) | UInt64(pair.composite)
        )
    }
    precondition(
        tables.compositionPairs == tables.compositionPairs.sorted(),
        "composition pairs not sorted"
    )
    precondition(
        Set(tables.compositionPairs.map { $0 >> 22 }).count == tables.compositionPairs.count,
        "duplicate composition pair keys"
    )

    return tables
}

/// Decodes a single code point straight from the built tables, exactly as the runtime does,
/// and returns the reconstructed semantic normalization data for round-trip verification.
func decode(_ codePoint: UInt32, _ tables: BuiltTables) -> ScalarNormData {
    var data = ScalarNormData()

    if codePoint >= trieLimit {
        return data
    }

    let blockRowIndex = Int(codePoint) >> blockShift
    let packedRowIndex = Int(tables.blockOffsets[blockRowIndex]) + (Int(codePoint) & blockMask)
    let value = tables.packedValues[packedRowIndex]
    let tag = Tag(rawValue: value >> 13)!
    let payload = Int(value & 0x1FFF)

    func nfdFromSlice(_ sliceIndex: Int) -> [(UInt32, UInt8)] {
        let entry = tables.decompositionSlices[sliceIndex]
        let offset = Int(entry >> 8)
        let length = Int(entry & 0xFF)
        return tables.decompositionScalars[offset..<(offset + length)].map {
            ($0 & 0x1F_FFFF, UInt8($0 >> 21))
        }
    }

    switch tag {
    case .inert, .hangulSyllable:
        break
    case .cccOnly:
        data.ccc = UInt8(payload)
    case .maybe:
        data.ccc = UInt8(payload)
        data.quickCheck = .maybe
    case .maybeWithDecomposition:
        data.quickCheck = .maybe
        data.nfd = nfdFromSlice(payload)
    case .decompositionQCYes:
        data.nfd = nfdFromSlice(payload)
    case .decompositionQCNo:
        data.quickCheck = .no
        data.nfd = nfdFromSlice(payload)
    }
    return data
}

func verify(_ normData: [ScalarNormData], _ pairs: [CompositionPair], _ tables: BuiltTables) {
    for codePoint in 0...maxCodePoint {
        var expected = normData[Int(codePoint)]
        if codePoint >= hangulSyllableBase, codePoint <= hangulSyllableEnd {
            /// Hangul syllables decode as plain data; the algorithmic decomposition is the
            /// runtime's responsibility and is verified by the unit tests instead.
            expected = ScalarNormData()
        }
        /// The trie stores the ccc of NFC_QC=No decomposable scalars only inside their
        /// decomposition elements, never as a standalone payload. The only scalars with both a
        /// decomposition and a nonzero ccc are NFC_QC=No, and their standalone ccc is never
        /// consulted at runtime: the quick check bails on the tag alone, and the normalizer
        /// replaces them with their decomposition before any reordering.
        if !expected.nfd.isEmpty {
            precondition(
                expected.ccc == 0 || expected.quickCheck == .no,
                "Decomposable scalar with nonzero ccc is not NFC_QC=No at "
                    + "U+\(String(codePoint, radix: 16, uppercase: true))"
            )
            expected.ccc = 0
        }

        let decoded = decode(codePoint, tables)
        guard decoded == expected else {
            fatalError(
                "Round-trip mismatch at U+\(String(codePoint, radix: 16, uppercase: true)): "
                    + "expected \(expected), got \(decoded)"
            )
        }
    }
    print("Round-trip verification passed for \(maxCodePoint + 1) code points.")

    for pair in pairs {
        let key = (UInt64(pair.first) << 43) | (UInt64(pair.second) << 22)
        var low = 0
        var high = tables.compositionPairs.count
        var found: UInt64? = nil
        while low < high {
            let mid = (low + high) / 2
            let candidate = tables.compositionPairs[mid]
            if (candidate >> 22) == (key >> 22) {
                found = candidate & 0x3F_FFFF
                break
            } else if candidate < key {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard found == UInt64(pair.composite) else {
            fatalError(
                "Composition pair binary search failed for "
                    + "U+\(String(pair.first, radix: 16, uppercase: true)) + "
                    + "U+\(String(pair.second, radix: 16, uppercase: true))"
            )
        }
    }
    print("Binary search verification passed for \(pairs.count) composition pairs.")
}

/// Asserts every data property the runtime implementation relies on, so that a future Unicode
/// version that breaks any of them turns into a loud generator failure instead of silent
/// misbehavior.
func verifyRuntimeAssumptions(_ normData: [ScalarNormData], _ pairs: [CompositionPair]) {
    var maxNonInert: UInt32 = 0
    var minNonInert: UInt32 = maxCodePoint
    var minNonInertForQuickCheck: UInt32 = maxCodePoint
    var maxNFDScalarsPerUTF8Byte = 0.0
    var maxNFDUTF8BytesPerUTF8Byte = 0.0

    for codePoint in 0...maxCodePoint {
        let data = normData[Int(codePoint)]
        let isHangul = codePoint >= hangulSyllableBase && codePoint <= hangulSyllableEnd
        let isInert = data == ScalarNormData() && !isHangul

        if !isInert {
            maxNonInert = max(maxNonInert, codePoint)
            minNonInert = min(minNonInert, codePoint)
            if data.ccc != 0 || data.quickCheck != .yes {
                minNonInertForQuickCheck = min(minNonInertForQuickCheck, codePoint)
            }
        }

        if !data.nfd.isEmpty {
            precondition(
                data.nfd.count <= 4,
                "NFD expansion longer than 4 scalars at "
                    + "U+\(String(codePoint, radix: 16, uppercase: true))"
            )
            for (scalar, ccc) in data.nfd {
                precondition(
                    normData[Int(scalar)].nfd.isEmpty,
                    "NFD expansion not fully recursive at "
                        + "U+\(String(codePoint, radix: 16, uppercase: true))"
                )
                precondition(
                    normData[Int(scalar)].ccc == ccc,
                    "NFD expansion has stale ccc at "
                        + "U+\(String(codePoint, radix: 16, uppercase: true))"
                )
            }

            let utf8Length = Double(Unicode.Scalar(codePoint)!.utf8.count)
            let nfdScalars = Double(data.nfd.count)
            let nfdUTF8Length = Double(
                data.nfd.reduce(into: 0) { $0 += Unicode.Scalar($1.0)!.utf8.count }
            )
            maxNFDScalarsPerUTF8Byte = max(maxNFDScalarsPerUTF8Byte, nfdScalars / utf8Length)
            maxNFDUTF8BytesPerUTF8Byte = max(maxNFDUTF8BytesPerUTF8Byte, nfdUTF8Length / utf8Length)
        }
    }

    /// The runtime trie lookup treats everything at or above the trie limit as inert.
    precondition(
        maxNonInert < trieLimit,
        "Normalization-relevant code point U+\(String(maxNonInert, radix: 16, uppercase: true)) "
            + "at or above the trie limit; bump trieLimit and CSWIFT_IDNA_NFC_TRIE_LIMIT together"
    )
    /// The normalizer emits scalars below 0xC0 directly without a trie lookup.
    precondition(
        minNonInert >= 0xC0,
        "Normalization-relevant code point below U+00C0: "
            + "U+\(String(minNonInert, radix: 16, uppercase: true))"
    )
    /// The quick check skips scalars below 0x300 without a trie lookup, and relies on all
    /// UTF-8 bytes below 0xCC only encoding such scalars.
    precondition(
        minNonInertForQuickCheck >= 0x300,
        "NFC_QC!=Yes or ccc!=0 code point below U+0300: "
            + "U+\(String(minNonInertForQuickCheck, radix: 16, uppercase: true))"
    )
    /// The normalizer sizes its scalar scratch buffer as 2x the input UTF-8 byte count,
    /// and its output buffer as 3x the input UTF-8 byte count.
    precondition(
        maxNFDScalarsPerUTF8Byte <= 2.0,
        "NFD expansion exceeds 2 scalars per input UTF-8 byte: \(maxNFDScalarsPerUTF8Byte)"
    )
    precondition(
        maxNFDUTF8BytesPerUTF8Byte <= 3.0,
        "NFD expansion exceeds 3 UTF-8 bytes per input UTF-8 byte: \(maxNFDUTF8BytesPerUTF8Byte)"
    )

    for pair in pairs {
        /// The normalizer only attempts composition when the current scalar is tagged
        /// maybe/maybeWithDecomposition, and only ever composes onto a ccc=0 starter.
        precondition(
            normData[Int(pair.second)].quickCheck == .maybe,
            "Composition pair second is not NFC_QC=Maybe: "
                + "U+\(String(pair.second, radix: 16, uppercase: true))"
        )
        precondition(
            normData[Int(pair.first)].ccc == 0,
            "Composition pair first has nonzero ccc: "
                + "U+\(String(pair.first, radix: 16, uppercase: true))"
        )
        precondition(
            normData[Int(pair.composite)].ccc == 0,
            "Composition pair composite has nonzero ccc: "
                + "U+\(String(pair.composite, radix: 16, uppercase: true))"
        )
        /// Jamo and Hangul syllables must stay out of the pair table; the runtime handles them
        /// arithmetically before the binary search.
        precondition(
            pair.composite < hangulSyllableBase || pair.composite > hangulSyllableEnd,
            "Hangul syllable in composition pair table"
        )
        /// Together with the NFD expansion byte bound, this guarantees composition never grows
        /// the normalizer's output beyond 3 UTF-8 bytes per input UTF-8 byte.
        precondition(
            Unicode.Scalar(pair.composite)!.utf8.count
                <= Unicode.Scalar(pair.first)!.utf8.count
                + Unicode.Scalar(pair.second)!.utf8.count,
            "Composition pair composite has a longer UTF-8 encoding than its parts: "
                + "U+\(String(pair.composite, radix: 16, uppercase: true))"
        )
    }

    print(
        "Runtime assumptions verified: maxNonInert=U+\(String(maxNonInert, radix: 16, uppercase: true)) "
            + "minNonInert=U+\(String(minNonInert, radix: 16, uppercase: true)) "
            + "minQuickCheckRelevant=U+\(String(minNonInertForQuickCheck, radix: 16, uppercase: true)) "
            + "maxNFDScalarsPerByte=\(maxNFDScalarsPerUTF8Byte) "
            + "maxNFDBytesPerByte=\(maxNFDUTF8BytesPerUTF8Byte)"
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
        // This file is generated by the utils/NFCTableGenerator.swift script.

        #include "../include/CSwiftIDNA.h"
        #include <stdint.h>

        """

    emitArray("uint16_t", "cswift_idna_nfc_block_offsets", tables.blockOffsets, into: &code)
    emitArray("uint16_t", "cswift_idna_nfc_packed_values", tables.packedValues, into: &code)
    emitArray(
        "uint32_t",
        "cswift_idna_nfc_decomposition_slices",
        tables.decompositionSlices,
        into: &code
    )
    emitArray(
        "uint32_t",
        "cswift_idna_nfc_decomposition_scalars",
        tables.decompositionScalars,
        into: &code
    )
    emitArray(
        "uint64_t",
        "cswift_idna_nfc_composition_pairs",
        tables.compositionPairs,
        perLine: 8,
        into: &code
    )
    code += """
        const int32_t cswift_idna_nfc_composition_pairs_count = \(tables.compositionPairs.count);

        """

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

    var ucd = ParsedUCD()

    print("Downloading \(unicodeDataURL) ...")
    let unicodeDataFile = try! fetchWithRetries(url: URL(string: unicodeDataURL)!)
    print("Downloaded \(unicodeDataFile.count) bytes")
    parseUnicodeData(String(decoding: unicodeDataFile, as: UTF8.self), into: &ucd)

    print("Downloading \(derivedNormalizationPropsURL) ...")
    let propsFile = try! fetchWithRetries(url: URL(string: derivedNormalizationPropsURL)!)
    print("Downloaded \(propsFile.count) bytes")
    parseDerivedNormalizationProps(String(decoding: propsFile, as: UTF8.self), into: &ucd)

    print(
        "Parsed: canonicalDecompositions=\(ucd.canonicalDecompositions.count) "
            + "fullCompositionExclusions=\(ucd.fullCompositionExclusions.count)"
    )

    let normData = computeNormData(ucd)
    let pairs = computeCompositionPairs(ucd)
    print("Computed: compositionPairs=\(pairs.count)")

    verifyRuntimeAssumptions(normData, pairs)

    let tables = build(normData, pairs)
    print(
        "Built: blockOffsets=\(tables.blockOffsets.count) packedValues=\(tables.packedValues.count) "
            + "decompositionSlices=\(tables.decompositionSlices.count) "
            + "decompositionScalars=\(tables.decompositionScalars.count) "
            + "compositionPairs=\(tables.compositionPairs.count) (shift=\(blockShift))"
    )
    let totalBytes =
        tables.blockOffsets.count * 2
        + tables.packedValues.count * 2
        + tables.decompositionSlices.count * 4
        + tables.decompositionScalars.count * 4
        + tables.compositionPairs.count * 8
    let totalKB = String(format: "%.1f", Double(totalBytes) / 1024)
    print("Total table bytes: \(totalBytes) (\(totalKB) KB)")

    verify(normData, pairs, tables)

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
