public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct DecodedUnicodeScalars: ~Copyable {
    @usableFromInline
    var scalars: RigidArray<Unicode.Scalar>

    @inlinable
    var count: Int {
        self.scalars.count
    }

    @inlinable
    @_lifetime(borrow utf8Bytes)
    init(utf8Bytes: Span<UInt8>) {
        self.scalars = RigidArray<Unicode.Scalar>(capacity: utf8Bytes.count)
        self.decode(utf8Bytes: utf8Bytes)
    }

    @usableFromInline
    subscript(index: Int) -> Unicode.Scalar {
        self.scalars[index]
    }

    @usableFromInline
    @_lifetime(borrow utf8Bytes)
    mutating func decode(utf8Bytes: Span<UInt8>) {
        var unicodeScalarsIterator = UnicodeScalarIterator()
        while let scalar = unicodeScalarsIterator.next(in: utf8Bytes) {
            self.scalars.append(scalar)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension DecodedUnicodeScalars {
    @usableFromInline
    struct Subsequence: ~Copyable {
        @usableFromInline
        var base: DecodedUnicodeScalars
        @usableFromInline
        var startIndex: Int
        @usableFromInline
        var endIndex: Int
        @usableFromInline
        var endIndexByteOffset: Int

        @inlinable
        var count: Int {
            self.endIndex - self.startIndex
        }

        /// Before using the subsequence, you need to set the starting byte using `set(startingByte:)`.
        @inlinable
        init(base: consuming DecodedUnicodeScalars) {
            self.base = base
            self.startIndex = 0
            self.endIndex = 0
            self.endIndexByteOffset = 0
        }

        /// As an optimization, this function assumes the new range is after the last range it was set to.
        /// As always, tests will catch the issue if it's not the case.
        @inlinable
        @_lifetime(&self)
        mutating func set(range: Range<Int>) {
            let scalarsCount = self.base.count
            var byteOffset = self.endIndexByteOffset

            if range.lowerBound == 0 {
                self.startIndex = 0
            } else {
                for idx in self.endIndex..<scalarsCount {
                    let scalar = self.base.scalars[idx]
                    byteOffset &+= scalar.utf8.count
                    if byteOffset == range.lowerBound {
                        self.startIndex = idx &+ 1
                        break
                    }
                }
            }

            for idx in self.startIndex..<scalarsCount {
                let scalar = self.base.scalars[idx]
                byteOffset &+= scalar.utf8.count
                if byteOffset == range.upperBound {
                    self.endIndex = idx &+ 1
                    self.endIndexByteOffset = byteOffset
                    break
                }
            }
        }

        /// Decodes and returns the unicode scalar at the given index.
        @inlinable
        subscript(index: Int) -> Unicode.Scalar {
            /// This assert is to trap in tests for the most part.
            /// That's why it's not a precondition.
            assert(self.endIndex > index, "Index out of bounds")
            return self.base[self.startIndex &+ index]
        }
    }
}
