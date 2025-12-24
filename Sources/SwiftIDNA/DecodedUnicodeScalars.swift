public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct DecodedUnicodeScalars: ~Copyable, ~Escapable {
    @usableFromInline
    var utf8Bytes: Span<UInt8>
    /// [index in unicodeScalars] -> [index in utf8]
    @usableFromInline
    var utf8Indices: RigidArray<Int>

    @inlinable
    var count: Int {
        self.utf8Indices.count
    }

    @inlinable
    @_lifetime(borrow utf8Bytes)
    init(utf8Bytes: Span<UInt8>) {
        self.utf8Bytes = utf8Bytes
        self.utf8Indices = RigidArray<Int>(capacity: utf8Bytes.count)
        self.decode()
    }

    /// Decodes and returns the unicode scalar at the given index.
    @usableFromInline
    subscript(index: Int) -> Unicode.Scalar {
        let endIndex = self.utf8Indices[index]
        let startIndex = index == 0 ? 0 : self.utf8Indices[index &- 1]
        let range = Range<Int>(uncheckedBounds: (startIndex, endIndex))

        var encodedScalar = Unicode.UTF8.EncodedScalar()
        for idx in range {
            encodedScalar.append(self.utf8Bytes[unchecked: idx])
        }

        return UTF8.decode(encodedScalar)
    }

    @usableFromInline
    mutating func decode() {
        var unicodeScalarsIterator = UnicodeScalarIterator()
        var idx = 0
        while let utf8Count = unicodeScalarsIterator.nextScalarLength(in: self.utf8Bytes) {
            idx &+= utf8Count
            self.utf8Indices.append(idx)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension DecodedUnicodeScalars {
    @usableFromInline
    struct Subsequence: ~Copyable, ~Escapable {
        @usableFromInline
        var base: DecodedUnicodeScalars
        @usableFromInline
        var startIndex: Int
        @usableFromInline
        var endIndex: Int

        @inlinable
        var count: Int {
            self.endIndex - self.startIndex
        }

        /// Before using the subsequence, you need to set the starting byte using `set(startingByte:)`.
        @inlinable
        @_lifetime(copy base)
        init(base: consuming DecodedUnicodeScalars) {
            self.base = base
            self.startIndex = 0
            self.endIndex = 0
        }

        /// As an optimization, this function assumes the new range is after the last range it was set to.
        /// As always, tests will catch the issue if it's not the case.
        @inlinable
        @_lifetime(&self)
        mutating func set(range: Range<Int>) {
            let utf8IndicesCount = self.base.utf8Indices.count

            if range.lowerBound == 0 {
                self.startIndex = 0
            } else {
                let minStartIndex = self.endIndex
                for idx in minStartIndex..<utf8IndicesCount {
                    if self.base.utf8Indices[idx] == range.lowerBound {
                        self.startIndex = idx &+ 1
                        break
                    }
                }
            }

            for idx in self.startIndex..<utf8IndicesCount {
                if self.base.utf8Indices[idx] == range.upperBound {
                    self.endIndex = idx &+ 1
                    break
                }
            }
        }

        /// Decodes and returns the unicode scalar at the given index.
        @inlinable
        subscript(index: Int) -> Unicode.Scalar {
            assert(self.endIndex > index, "Index out of bounds")
            return self.base[self.startIndex &+ index]
        }
    }
}
