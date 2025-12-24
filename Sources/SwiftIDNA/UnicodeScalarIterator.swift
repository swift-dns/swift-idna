@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct UnicodeScalarIterator: ~Copyable {
    @usableFromInline
    var currentCodeUnitOffset: Int

    @inlinable
    init() {
        self.currentCodeUnitOffset = 0
    }

    /// Only pass the span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inlinable
    @_lifetime(borrow bytes)
    mutating func next(in bytes: Span<UInt8>) -> Unicode.Scalar? {
        guard self.currentCodeUnitOffset < bytes.count else { return nil }

        let firstByte = bytes[unchecked: self.currentCodeUnitOffset]

        if firstByte.isASCII {
            self.currentCodeUnitOffset &+= 1
            return Unicode.Scalar(firstByte)
        }

        let scalarLength = (~firstByte).leadingZeroBitCount

        var encodedScalar = UTF8.EncodedScalar()
        for idx in 0..<scalarLength {
            encodedScalar.append(bytes[unchecked: self.currentCodeUnitOffset &+ idx])
        }

        let scalar = UTF8.decode(encodedScalar)
        self.currentCodeUnitOffset &+= scalarLength

        return scalar
    }
}
