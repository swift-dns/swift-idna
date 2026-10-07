#if !($Embedded || os(WASI))
internal import Highway
#endif

/// Checks if bytes are well-formed UTF-8.
/// [Unicode Standard, Table 3-7. Well-Formed UTF-8 Byte Sequences](https://www.unicode.org/versions/Unicode18.0.0/core-spec/chapter-3/#G27506)
@available(SwiftStdlib 5.1, *)
package enum UTF8Checker {

    static var windowSize: Int { 16 }

    /// Returns true if `bytes` contains only valid UTF-8 bytes.
    @inline(always)
    static func isWellFormed(_ bytes: Span<UInt8>) -> Bool {
        #if $Embedded || os(WASI)
        return Self.isWellFormed_SlowPath(bytes)
        #else
        return Self.isWellFormed_FastPath(bytes)
        #endif
    }
}

@available(SwiftStdlib 5.1, *)
extension UTF8Checker {
    /// Checks windows of `windowSize` bytes, each byte along with its 3 preceding bytes, in a way
    /// that LLVM auto-vectorizes.
    package static func isWellFormed_SlowPath(_ bytes: Span<UInt8>) -> Bool {
        let count = bytes.count
        let windowSize = Self.windowSize
        if count &+ 3 <= windowSize &* 3 {
            return withUnsafeTemporaryAllocation(
                of: UInt8.self,
                capacity: windowSize &* 3 &+ 3
            ) { paddedBytes in
                unsafe paddedBytes.initialize(repeating: 0)
                let paddedBytesBuffer = unsafe UnsafeMutableRawBufferPointer(
                    rebasing: UnsafeMutableRawBufferPointer(paddedBytes)[3...]
                )
                bytes.withUnsafeBytes { rawBytes in
                    unsafe paddedBytesBuffer.copyMemory(from: rawBytes)
                }
                /// The zero bytes after `bytes` also catch a sequence that is cut off at the end.
                let lastWindowStart = count / windowSize &* windowSize &+ 3
                let errorBits = unsafe Self.errorBits_RequiringThreeToeroomBytes(
                    ofWindowsIn: paddedBytes.span,
                    from: 3,
                    through: lastWindowStart
                )
                return errorBits & 0x80 == 0
            }
        }

        var errorBits = withUnsafeTemporaryAllocation(
            of: UInt8.self,
            capacity: windowSize &+ 3
        ) { headBytes in
            unsafe headBytes.initialize(repeating: 0)
            let headBytesBuffer = unsafe UnsafeMutableRawBufferPointer(
                rebasing: UnsafeMutableRawBufferPointer(headBytes)[3...]
            )
            bytes.withUnsafeBytes { rawBytes in
                unsafe headBytesBuffer.copyMemory(
                    from: UnsafeRawBufferPointer(rebasing: rawBytes[..<windowSize])
                )
            }
            return unsafe Self.errorBits_RequiringThreeToeroomBytes(
                ofWindowsIn: headBytes.span,
                from: 3,
                through: 3
            )
        }
        errorBits |= Self.errorBits_RequiringThreeToeroomBytes(
            ofWindowsIn: bytes,
            from: windowSize,
            through: count &- windowSize
        )
        errorBits |= Self.errorBits(
            byte: 0,
            prev1: unsafe bytes[unchecked: count &- 1],
            prev2: unsafe bytes[unchecked: count &- 2],
            prev3: unsafe bytes[unchecked: count &- 3]
        )
        return errorBits & 0x80 == 0
    }

    /// Ors the `errorBits(ofWindowIn:at:)` of the windows at `start`, `start + windowSize` and so
    /// on, plus the one at `lastStart`, which can overlap the window before it.
    /// Intentionally `@inline(never)`, so LLVM vectorizes the windows the same way for every caller.
    @inline(never)
    static func errorBits_RequiringThreeToeroomBytes(
        ofWindowsIn bytes: Span<UInt8>,
        from start: Int,
        through lastStart: Int
    ) -> UInt8 {
        assert(start >= 3)
        var errorBits: UInt8 = 0
        var windowStart = start
        while windowStart < lastStart {
            errorBits |= Self.errorBits_RequiringThreeToeroomBytes(
                ofWindowIn: bytes,
                at: windowStart
            )
            windowStart &+= Self.windowSize
        }
        errorBits |= Self.errorBits_RequiringThreeToeroomBytes(ofWindowIn: bytes, at: lastStart)
        return errorBits
    }

    /// Ors the `errorBits(byte:prev1:prev2:prev3:)` of the `windowSize` bytes from `start`, each
    /// with its 3 preceding bytes.
    @inline(always)
    static func errorBits_RequiringThreeToeroomBytes(
        ofWindowIn bytes: Span<UInt8>,
        at start: Int
    ) -> UInt8 {
        assert(bytes.count >= start &+ Self.windowSize)
        var errorBits: UInt8 = 0
        /// This loop is auto-vectorized by LLVM.
        for offset in 0..<Self.windowSize {
            let idx = start &+ offset
            errorBits |= Self.errorBits(
                byte: unsafe bytes[unchecked: idx],
                prev1: unsafe bytes[unchecked: idx &- 1],
                prev2: unsafe bytes[unchecked: idx &- 2],
                prev3: unsafe bytes[unchecked: idx &- 3]
            )
        }
        return errorBits
    }

    /// The highest bit is set if `byte` can't follow `prev1`, `prev2` and `prev3` in well-formed
    /// UTF-8. Other bits are meaningless.
    /// Branchless, so LLVM can vectorize the loops calling it.
    /// Intentionally `@inline(__always)`, since with `@inline(always)` LLVM doesn't vectorize the
    /// loops calling it.
    @inline(__always)
    static func errorBits(byte: UInt8, prev1: UInt8, prev2: UInt8, prev3: UInt8) -> UInt8 {
        let isContinuation = byte & ~(byte &<< 1)
        let mustBeContinuation =
            Self.saturatingSubtract(prev1, 0x40)
            | Self.saturatingSubtract(prev2, 0x60)
            | Self.saturatingSubtract(prev3, 0x70)
        let isInvalidLead =
            Self.saturatingSubtract(byte, 0x75) | Self.isEqual(byte & 0xFE, 0xC0)
        let isAtLeastA0 = byte &<< 2
        let isAtLeast90 = (byte | (byte &<< 1)) &<< 2
        let isOutOfSecondByteRange =
            (Self.isEqual(prev1, 0xE0) & ~isAtLeastA0)
            | (Self.isEqual(prev1, 0xED) & isAtLeastA0)
            | (Self.isEqual(prev1, 0xF0) & ~isAtLeast90)
            | (Self.isEqual(prev1, 0xF4) & isAtLeast90)
        return (isContinuation ^ mustBeContinuation) | isInvalidLead | isOutOfSecondByteRange
    }

    @inline(always)
    static func saturatingSubtract(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
        lhs &- Swift.min(lhs, rhs)
    }

    /// `0x80` if `lhs == rhs`, otherwise `0`.
    @inline(always)
    static func isEqual(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
        Self.saturatingSubtract(1, lhs ^ rhs) &<< 7
    }
}

#if !($Embedded || os(WASI))
@available(SwiftStdlib 5.1, *)
extension UTF8Checker {
    /// A port of [simdutf's lookup algorithm](https://github.com/simdutf/simdutf/blob/v9.2.1/src/generic/utf8_validation/utf8_lookup4_algorithm.h).
    /// Copyright 2021 The simdutf authors, used under the [Apache License 2.0](https://github.com/simdutf/simdutf/blob/v9.2.1/LICENSE-APACHE).
    /// The algorithm is described in [Validating UTF-8 In Less Than One Instruction Per Byte](https://arxiv.org/abs/2010.03090).
    ///
    /// Intentionally `@inline(never)`, so the vector code is not copied into every caller.
    @inline(never)
    static func isWellFormed_FastPath(_ bytes: Span<UInt8>) -> Bool {
        let count = bytes.count
        guard count > 0 else {
            return true
        }

        let laneCount = HighwayUInt8.laneCount
        guard _fastPath(laneCount >= LookupTables.minimumLaneCount) else {
            return Self.isWellFormed_SlowPath(bytes)
        }

        let tables = LookupTables()
        let headBytes = HighwayUInt8.loadFirst(from: bytes)
        var errors = Self.lookupErrors(
            input: headBytes,
            prev1: HighwayUInt8.slide1Up(headBytes),
            prev2: HighwayUInt8.slideUpLanes(headBytes, by: 2),
            prev3: HighwayUInt8.slideUpLanes(headBytes, by: 3),
            tables: tables
        )

        if count > laneCount {
            var remainingBytesSpan = unsafe bytes.extracting(
                unchecked: Range<Int>(uncheckedBounds: (laneCount &- 3, count))
            )
            while remainingBytesSpan.count >= laneCount &+ 3 {
                errors = HighwayUInt8.bitwiseOr(
                    errors,
                    Self.lookupErrors(window: remainingBytesSpan, tables: tables)
                )
                let remainingBytesRange = unsafe Range<Int>(
                    uncheckedBounds: (laneCount, remainingBytesSpan.count)
                )
                remainingBytesSpan = unsafe remainingBytesSpan.extracting(
                    unchecked: remainingBytesRange
                )
            }
            if remainingBytesSpan.count > 3 {
                errors = HighwayUInt8.bitwiseOr(
                    errors,
                    Self.lookupErrors(lastWindow: remainingBytesSpan, tables: tables)
                )
            }
        }

        if count >= 3 {
            let last = unsafe bytes[unchecked: count &- 1]
            let secondToLast = unsafe bytes[unchecked: count &- 2]
            let thirdToLast = unsafe bytes[unchecked: count &- 3]
            if last >= 0xC0 || secondToLast >= 0xE0 || thirdToLast >= 0xF0 {
                return false
            }
        }

        return HighwayUInt8.allFalse(HighwayUInt8.notEqualTo(errors, HighwayUInt8.zero()))
    }

    /// The errors of the `laneCount` bytes after the first 3 bytes of `bytes`.
    @inline(always)
    static func lookupErrors(
        window bytes: Span<UInt8>,
        tables: LookupTables
    ) -> HighwayUInt8.Vector {
        let count = bytes.count
        return unsafe Self.lookupErrors(
            input: HighwayUInt8.load(
                fromUnchecked: bytes.extracting(unchecked: Range(uncheckedBounds: (3, count)))
            ),
            prev1: HighwayUInt8.load(
                fromUnchecked: bytes.extracting(unchecked: Range(uncheckedBounds: (2, count)))
            ),
            prev2: HighwayUInt8.load(
                fromUnchecked: bytes.extracting(unchecked: Range(uncheckedBounds: (1, count)))
            ),
            prev3: HighwayUInt8.load(fromUnchecked: bytes),
            tables: tables
        )
    }

    /// The errors of the bytes after the first 3 bytes of `bytes`, which are fewer than
    /// `laneCount`.
    @inline(always)
    static func lookupErrors(
        lastWindow bytes: Span<UInt8>,
        tables: LookupTables
    ) -> HighwayUInt8.Vector {
        let count = bytes.count
        return unsafe Self.lookupErrors(
            input: HighwayUInt8.loadFirst(
                from: bytes.extracting(unchecked: Range(uncheckedBounds: (3, count)))
            ),
            prev1: HighwayUInt8.loadFirst(
                from: bytes.extracting(unchecked: Range(uncheckedBounds: (2, count)))
            ),
            prev2: HighwayUInt8.loadFirst(
                from: bytes.extracting(unchecked: Range(uncheckedBounds: (1, count)))
            ),
            prev3: HighwayUInt8.loadFirst(from: bytes),
            tables: tables
        )
    }

    /// Nonzero lanes are errors.
    /// simdutf's `check_special_cases` and `check_multibyte_lengths`.
    @inline(always)
    static func lookupErrors(
        input: HighwayUInt8.Vector,
        prev1: HighwayUInt8.Vector,
        prev2: HighwayUInt8.Vector,
        prev3: HighwayUInt8.Vector,
        tables: LookupTables
    ) -> HighwayUInt8.Vector {
        let specialCases = HighwayUInt8.bitwiseAnd(
            HighwayUInt8.bitwiseAnd(
                HighwayUInt8.tableLookupBytes(
                    tables.byte1High,
                    HighwayUInt8.shiftedRight(prev1, by: 4)
                ),
                HighwayUInt8.tableLookupBytes(
                    tables.byte1Low,
                    HighwayUInt8.bitwiseAnd(prev1, HighwayUInt8.repeating(0x0F))
                )
            ),
            HighwayUInt8.tableLookupBytes(
                tables.byte2High,
                HighwayUInt8.shiftedRight(input, by: 4)
            )
        )
        let mustBe23Continuation = HighwayUInt8.bitwiseAnd(
            HighwayUInt8.bitwiseOr(
                HighwayUInt8.saturatingSubtracting(prev2, HighwayUInt8.repeating(0xE0 &- 0x80)),
                HighwayUInt8.saturatingSubtracting(prev3, HighwayUInt8.repeating(0xF0 &- 0x80))
            ),
            HighwayUInt8.repeating(0x80)
        )
        return HighwayUInt8.bitwiseXor(mustBe23Continuation, specialCases)
    }

    /// The lookup tables of [simdutf's `check_special_cases`](https://github.com/simdutf/simdutf/blob/v9.2.1/src/generic/utf8_validation/utf8_lookup4_algorithm.h).
    /// Copyright 2021 The simdutf authors, used under the [Apache License 2.0](https://github.com/simdutf/simdutf/blob/v9.2.1/LICENSE-APACHE).
    struct LookupTables {
        /// The lanes of the 128-bit blocks that `tableLookupBytes` looks up in.
        static var minimumLaneCount: Int {
            16
        }

        /// Indexed by the high nibble of the previous byte.
        let byte1High: HighwayUInt8.Vector
        /// Indexed by the low nibble of the previous byte.
        let byte1Low: HighwayUInt8.Vector
        /// Indexed by the high nibble of the current byte.
        let byte2High: HighwayUInt8.Vector

        @inline(always)
        init() {
            self.byte1High = HighwayUInt8.repeatingBlock(
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                128,
                128,
                128,
                128,
                33,
                1,
                21,
                73
            )
            self.byte1Low = HighwayUInt8.repeatingBlock(
                231,
                163,
                131,
                131,
                139,
                203,
                203,
                203,
                203,
                203,
                203,
                203,
                203,
                219,
                203,
                203
            )
            self.byte2High = HighwayUInt8.repeatingBlock(
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                230,
                174,
                186,
                186,
                1,
                1,
                1,
                1
            )
        }
    }
}
#endif
