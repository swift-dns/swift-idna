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
    #if swift(<6.3)
    @_lifetime(copy utf8Bytes)
    #endif
    init(utf8Bytes: Span<UInt8>) {
        self.scalars = RigidArray<Unicode.Scalar>(capacity: utf8Bytes.count)
        self.decode(utf8Bytes: utf8Bytes)
    }

    @usableFromInline
    #if swift(<6.3)
    @_lifetime(copy utf8Bytes)
    #endif
    mutating func decode(utf8Bytes: Span<UInt8>) {
        self.scalars.edit { output in
            var unicodeScalarsIterator = UnicodeScalarIterator()
            while let scalar = unicodeScalarsIterator.next(in: utf8Bytes) {
                output.append(scalar)
            }
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension DecodedUnicodeScalars {
    @usableFromInline
    struct Subsequence: ~Copyable, ~Escapable {
        @usableFromInline
        var scalars: Span<Unicode.Scalar>
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
        ///
        /// We're using `inout` to ensure exclusive access.
        @inlinable
        @_lifetime(&base)
        init(base: inout DecodedUnicodeScalars) {
            self.scalars = base.scalars.span
            self.startIndex = 0
            self.endIndex = 0
            self.endIndexByteOffset = 0
        }

        /// As an optimization, this function assumes the new range is after the last range it was set to.
        /// As always, tests will catch the issue if it's not the case.
        @inlinable
        #if swift(<6.3)
        @_lifetime(&self)
        #endif
        mutating func set(range: Range<Int>) {
            let scalarsCount = self.scalars.count
            var byteOffset = self.endIndexByteOffset

            if range.lowerBound == 0 {
                self.startIndex = 0
            } else {
                for idx in self.endIndex..<scalarsCount {
                    let scalar = self.scalars[unchecked: idx]
                    byteOffset &+= scalar.utf8.count
                    if byteOffset == range.lowerBound {
                        self.startIndex = idx &+ 1
                        break
                    }
                }
            }

            for idx in self.startIndex..<scalarsCount {
                let scalar = self.scalars[unchecked: idx]
                byteOffset &+= scalar.utf8.count
                if byteOffset == range.upperBound {
                    self.endIndex = idx &+ 1
                    self.endIndexByteOffset = byteOffset
                    break
                }
            }
        }

        /// Returns the unicode scalar at the given index.
        @inlinable
        subscript(index: Int) -> Unicode.Scalar {
            /// This assert is to trap in tests for the most part.
            /// That's why it's not a precondition.
            assert(self.endIndex > index, "Index out of bounds")
            return self.scalars[unchecked: self.startIndex &+ index]
        }
    }
}
