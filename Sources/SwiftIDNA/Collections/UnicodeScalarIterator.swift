/// An iterator that decodes Unicode scalars from the same span of UTF-8 bytes.
@available(SwiftStdlib 5.1, *)
@usableFromInline
struct UnicodeScalarIterator {
    @usableFromInline
    var currentCodeUnitOffset: Int

    @inlinable
    init() {
        self.currentCodeUnitOffset = 0
    }

    /// Decodes and returns the next Unicode scalar and the range of utf8 bytes it was decoded from.
    /// Always tries to decode regardless if the uncode offset is valid.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func uncheckedNext(in bytes: Span<UInt8>) -> UInt32 {
        let lowerBound = self.currentCodeUnitOffset
        let leadByte = unsafe bytes[unchecked: lowerBound]
        let lastIndex = bytes.count &- 1
        let continuationByte1 = unsafe bytes[unchecked: Swift.min(lowerBound &+ 1, lastIndex)]
        let continuationByte2 = unsafe bytes[unchecked: Swift.min(lowerBound &+ 2, lastIndex)]
        let continuationByte3 = unsafe bytes[unchecked: Swift.min(lowerBound &+ 3, lastIndex)]

        let (scalarUTF8Length, uncheckedScalar) = Self.decodeScalar(
            leadByte: leadByte,
            continuationByte1: continuationByte1,
            continuationByte2: continuationByte2,
            continuationByte3: continuationByte3
        )
        self.currentCodeUnitOffset = lowerBound &+ scalarUTF8Length

        return uncheckedScalar
    }

    @inline(__always)
    @inlinable
    static func decodeScalar(
        leadByte: UInt8,
        continuationByte1: UInt8,
        continuationByte2: UInt8,
        continuationByte3: UInt8
    ) -> (scalarUTF8Length: Int, uncheckedScalar: UInt32) {
        /// Count of leading ones in the first byte: 0 for ASCII, else the scalar's byte-length
        let leadingOnes = Swift.min(4, (~leadByte).leadingZeroBitCount)
        let scalarUTF8Length = Swift.max(1, leadingOnes)

        let leadNoLengthBits = UInt32(leadByte & (0b0111_1111 &>> leadingOnes)) &<< 18
        let c1 = UInt32(continuationByte1 & 0b0011_1111) &<< 12
        let c2 = UInt32(continuationByte2 & 0b0011_1111) &<< 6
        let c3 = UInt32(continuationByte3 & 0b0011_1111)

        let shift = 6 &* (4 &- scalarUTF8Length)
        let value = (leadNoLengthBits | c1 | c2 | c3) &>> shift

        return (scalarUTF8Length, value)
    }

    /// Decodes and returns the next Unicode scalar.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func next(in bytes: Span<UInt8>) -> UInt32? {
        guard self.currentCodeUnitOffset < bytes.count else { return nil }
        return self.uncheckedNext(in: bytes)
    }

    /// Decodes and returns the next Unicode scalar and the range of utf8 bytes it was decoded from;
    /// without checking if the offset is valid.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func uncheckedNextWithRange(in bytes: Span<UInt8>) -> (UInt32, Range<Int>)? {
        let lowerBound = self.currentCodeUnitOffset
        let next = self.uncheckedNext(in: bytes)
        let range = unsafe Range<Int>(
            uncheckedBounds: (lowerBound, self.currentCodeUnitOffset)
        )
        return (next, range)
    }

    /// Decodes and returns the next Unicode scalar and the range of utf8 bytes it was decoded from.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func nextWithRange(in bytes: Span<UInt8>) -> (UInt32, Range<Int>)? {
        guard self.currentCodeUnitOffset < bytes.count else { return nil }
        let lowerBound = self.currentCodeUnitOffset
        let next = self.uncheckedNext(in: bytes)
        let range = unsafe Range<Int>(
            uncheckedBounds: (lowerBound, self.currentCodeUnitOffset)
        )
        return (next, range)
    }
}
