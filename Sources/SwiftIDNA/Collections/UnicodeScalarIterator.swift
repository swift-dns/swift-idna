/// An iterator that decodes Unicode scalars from the same span of UTF-8 bytes.
@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct UnicodeScalarIterator {
    @usableFromInline
    var currentCodeUnitOffset: Int

    @inlinable
    init() {
        self.currentCodeUnitOffset = 0
    }

    /// Decodes and returns the next Unicode scalar and the range of utf8 bytes it was decoded from.
    ///
    /// Only pass the span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inlinable
    mutating func nextWithRange(
        in bytes: Span<UInt8>
    ) -> (codePoint: Unicode.Scalar, range: Range<Int>)? {
        guard self.currentCodeUnitOffset < bytes.count else { return nil }

        let firstByte = bytes[unchecked: self.currentCodeUnitOffset]

        if firstByte.isASCII {
            let range = Range<Int>(
                uncheckedBounds: (self.currentCodeUnitOffset, self.currentCodeUnitOffset &+ 1)
            )
            self.currentCodeUnitOffset = range.upperBound
            return (Unicode.Scalar(firstByte), range)
        }

        let scalarLength = (~firstByte).leadingZeroBitCount

        var encodedScalar = UTF8.EncodedScalar()
        let range = Range<Int>(
            uncheckedBounds: (
                self.currentCodeUnitOffset, self.currentCodeUnitOffset &+ scalarLength
            )
        )
        for idx in range {
            encodedScalar.append(bytes[unchecked: idx])
        }

        let scalar = UTF8.decode(encodedScalar)
        self.currentCodeUnitOffset &+= scalarLength

        return (scalar, range)
    }

    /// Decodes and returns the next Unicode scalar.
    ///
    /// Only pass the span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inlinable
    mutating func next(in bytes: Span<UInt8>) -> Unicode.Scalar? {
        self.nextWithRange(in: bytes)?.codePoint
    }
}
