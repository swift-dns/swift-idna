/// Decodes UTF-8 into Unicode scalars a fixed-size window at a time.
///
/// Only pass the same span to any single decode/walk sequence; tests will fail otherwise.
@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct SIMDUnicodeScalarDecoder: ~Copyable, ~Escapable {
    /// Bytes decoded per window. Matches the natural byte-vector width.
    @usableFromInline
    package static var windowSize: Int { 16 }
    /// Extra bytes for speculative decoding.
    @usableFromInline
    static var tempBytesSize: Int { Self.windowSize &+ 3 }
    /// Leading always-zero slots of `paddedScalarUTF8Lengths`.
    @usableFromInline
    static var lengthsPadding: Int { 3 }
    @usableFromInline
    static var paddedScalarUTF8LengthsSize: Int { Self.lengthsPadding &+ Self.windowSize }
    @usableFromInline
    static var scalarStartOffsetsSize: Int { Self.windowSize &+ 1 }

    /// Temp storage for faster speculative decoding.
    /// Initialized to zeros via `withTemporaryDecoder(_:)`.
    /// Of length `Self.tempBytesSize`.
    @usableFromInline
    package var tempBytes: MutableSpan<UInt8>
    /// Decoded UTF-8 byte length (1...4) per window position, offset by `Self.lengthsPadding`.
    /// Of length `Self.paddedScalarUTF8LengthsSize`.
    @usableFromInline
    package var paddedScalarUTF8Lengths: MutableSpan<UInt8>
    /// Decoded scalar value per window position.
    /// Of length `Self.windowSize`.
    @usableFromInline
    package var uncheckedScalarValues: MutableSpan<UInt32>
    /// Densely packed window-relative scalar start offsets, with an end sentinel at `scalarCount`.
    /// Of length `Self.scalarStartOffsetsSize`.
    @usableFromInline
    package var scalarStartOffsets: MutableSpan<UInt8>
    @usableFromInline
    package var scalarCount: Int

    @inlinable
    @_lifetime(
        copy tempBytes,
        copy paddedScalarUTF8Lengths,
        copy uncheckedScalarValues,
        copy scalarStartOffsets
    )
    init(
        tempBytes: consuming MutableSpan<UInt8>,
        paddedScalarUTF8Lengths: consuming MutableSpan<UInt8>,
        uncheckedScalarValues: consuming MutableSpan<UInt32>,
        scalarStartOffsets: consuming MutableSpan<UInt8>
    ) {
        self.tempBytes = tempBytes
        self.paddedScalarUTF8Lengths = paddedScalarUTF8Lengths
        self.uncheckedScalarValues = uncheckedScalarValues
        self.scalarStartOffsets = scalarStartOffsets
        self.scalarCount = 0
    }

    /// Runs `body` with a decoder backed by temporary stack allocations.
    @inlinable
    @inline(__always)
    package static func withTemporaryDecoder<R: ~Copyable, Failure: Error>(
        _ body: (inout SIMDUnicodeScalarDecoder) throws(Failure) -> R
    ) throws(Failure) -> R {
        try withUnsafeTemporaryAllocation(
            of: UInt8.self,
            capacity: Self.tempBytesSize
        ) { tempBytes throws(Failure) -> R in
            try withUnsafeTemporaryAllocation(
                of: UInt8.self,
                capacity: Self.paddedScalarUTF8LengthsSize
            ) { paddedScalarUTF8Lengths throws(Failure) -> R in
                try withUnsafeTemporaryAllocation(
                    of: UInt32.self,
                    capacity: Self.windowSize
                ) { uncheckedScalarValues throws(Failure) -> R in
                    try withUnsafeTemporaryAllocation(
                        of: UInt8.self,
                        capacity: Self.scalarStartOffsetsSize
                    ) { scalarStartOffsets throws(Failure) -> R in
                        unsafe tempBytes.initialize(repeating: 0)
                        unsafe paddedScalarUTF8Lengths.initialize(repeating: 0)
                        unsafe scalarStartOffsets.initialize(repeating: 0)
                        var decoder = unsafe SIMDUnicodeScalarDecoder(
                            tempBytes: tempBytes.mutableSpan,
                            paddedScalarUTF8Lengths: paddedScalarUTF8Lengths.mutableSpan,
                            uncheckedScalarValues: uncheckedScalarValues.mutableSpan,
                            scalarStartOffsets: scalarStartOffsets.mutableSpan
                        )
                        return try body(&decoder)
                    }
                }
            }
        }
    }

    /// Whether the positions reached by a lead byte 1...3 back are exactly the continuation
    /// bytes. Only then does walking the non-continuation bytes agree with walking the lengths.
    @inlinable
    @inline(__always)
    func isWindowWellFormed() -> Bool {
        var mismatches: UInt8 = 0
        /// This loop is auto-vectorized by LLVM.
        for idx in 0..<Self.windowSize {
            let byte = unsafe self.tempBytes[unchecked: idx]
            let isContinuation = (byte &>> 7) & ((~byte) &>> 6) & 1
            let oneBack = unsafe self.paddedScalarUTF8Lengths[unchecked: idx &+ 2]
            let twoBack = unsafe self.paddedScalarUTF8Lengths[unchecked: idx &+ 1]
            let threeBack = unsafe self.paddedScalarUTF8Lengths[unchecked: idx]
            let isCovered: UInt8 = (oneBack >= 2 || twoBack >= 3 || threeBack >= 4) ? 1 : 0
            mismatches |= isContinuation ^ isCovered
        }
        return mismatches == 0
    }

    /// Fills `scalarStartOffsets` with the non-continuation positions of a well-formed
    /// full-size window.
    @inlinable
    @inline(__always)
    mutating func compactWellFormedScalarStarts() {
        var count = 0
        for idx in 0..<Self.windowSize {
            unsafe self.scalarStartOffsets[unchecked: count] = UInt8(truncatingIfNeeded: idx)
            let byte = unsafe self.tempBytes[unchecked: idx]
            let continuationBit = (byte &>> 7) & ((~byte) &>> 6) & 1
            count &+= Int(1 &- continuationBit)
        }

        let lastStart = Int(unsafe self.scalarStartOffsets[unchecked: count &- 1])
        let lastLength = unsafe self.paddedScalarUTF8Lengths[
            unchecked: Self.lengthsPadding &+ lastStart
        ]
        unsafe self.scalarStartOffsets[unchecked: count] = UInt8(
            truncatingIfNeeded: lastStart &+ Int(lastLength)
        )
        self.scalarCount = count
    }

    /// Fills `scalarStartOffsets` by hopping through the decoded lengths.
    @inlinable
    @inline(__always)
    package mutating func chainScalarStarts(windowLength: Int) {
        var count = 0
        var idx = 0
        while idx < windowLength {
            unsafe self.scalarStartOffsets[unchecked: count] = UInt8(truncatingIfNeeded: idx)
            count &+= 1
            idx &+= Int(
                unsafe self.paddedScalarUTF8Lengths[unchecked: Self.lengthsPadding &+ idx]
            )
        }

        unsafe self.scalarStartOffsets[unchecked: count] = UInt8(truncatingIfNeeded: idx)
        self.scalarCount = count
    }

    @inlinable
    @inline(__always)
    mutating func _decodeWindow(of encodedBytes: Span<UInt8>, windowLength: Int) {
        assert(encodedBytes.count >= 0 && encodedBytes.count <= Self.tempBytesSize)
        assert(windowLength > 0 && windowLength <= Self.windowSize)
        assert(windowLength <= encodedBytes.count)

        /// Write `encodedBytes` into `tempBytes`.
        /// `tempBytes` is initialized-memory by above code (`tempBytes.initialize(repeating: 0)`), so it's valid anyway.
        /// The pad bytes are not important.
        tempBytes.withUnsafeMutableBufferPointer { temp in
            encodedBytes.withUnsafeBufferPointer { encoded in
                let rawTemp = UnsafeMutableRawBufferPointer(temp)
                let rawEncodedBytes = UnsafeRawBufferPointer(encoded)
                unsafe rawTemp.copyMemory(from: rawEncodedBytes)
            }
        }

        /// This loop is auto-vectorized by LLVM.
        for idx in 0..<Self.windowSize {
            let leadByte = unsafe tempBytes[unchecked: idx]
            /// We have 3 extra bytes for speculative decoding so we won't run out of bytes.
            /// See `tempBytes` doc comments.
            let continuationByte1 = unsafe tempBytes[unchecked: idx &+ 1]
            let continuationByte2 = unsafe tempBytes[unchecked: idx &+ 2]
            let continuationByte3 = unsafe tempBytes[unchecked: idx &+ 3]

            let (scalarUTF8Length, uncheckedScalar) = UnicodeScalarIterator.decodeScalar(
                leadByte: leadByte,
                continuationByte1: continuationByte1,
                continuationByte2: continuationByte2,
                continuationByte3: continuationByte3
            )
            unsafe self.paddedScalarUTF8Lengths[
                unchecked: Self.lengthsPadding &+ idx
            ] = UInt8(
                truncatingIfNeeded: scalarUTF8Length
            )
            unsafe self.uncheckedScalarValues[unchecked: idx] = uncheckedScalar
        }

        if windowLength == Self.windowSize, self.isWindowWellFormed() {
            self.compactWellFormedScalarStarts()
        } else {
            self.chainScalarStarts(windowLength: windowLength)
        }
    }

    /// Decodes the window starting at `startIdx`, populating `scalarStartOffsets` and `scalarCount`.
    @inlinable
    @inline(__always)
    package mutating func decodeNextWindow(
        of bytes: Span<UInt8>,
        startIdx: Int
    ) {
        let totalCount = bytes.count
        let lowerBound = startIdx
        let upperBound = min(lowerBound &+ Self.tempBytesSize, totalCount)
        let windowEnd = min(lowerBound &+ Self.windowSize, totalCount)
        let decodeRange = unsafe Range<Int>(
            uncheckedBounds: (lowerBound, upperBound)
        )
        let span = unsafe bytes.extracting(unchecked: decodeRange)
        self._decodeWindow(of: span, windowLength: windowEnd &- lowerBound)
    }

    @inlinable
    @inline(__always)
    func scalarStartOffset(at scalarIdx: Int) -> Int {
        Int(unsafe self.scalarStartOffsets[unchecked: scalarIdx])
    }

    @inlinable
    @inline(__always)
    func scalarUTF8Length(at scalarIdx: Int) -> Int {
        let start = unsafe self.scalarStartOffsets[unchecked: scalarIdx]
        let end = unsafe self.scalarStartOffsets[unchecked: scalarIdx &+ 1]
        return Int(end &- start)
    }

    @inlinable
    @inline(__always)
    func windowEndOffset() -> Int {
        Int(unsafe self.scalarStartOffsets[unchecked: self.scalarCount])
    }
}
