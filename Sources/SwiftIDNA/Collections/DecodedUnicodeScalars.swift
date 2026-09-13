public import BasicContainers

/// A container that holds a group of decoded Unicode scalars.
@available(SwiftStdlib 5.1, *)
@usableFromInline
struct DecodedUnicodeScalars: ~Copyable {
    @usableFromInline
    var scalars: RigidArray<Unicode.Scalar>

    @inlinable
    init(utf8Bytes: Span<UInt8>, errors: inout IDNA.MappingErrors) {
        self.scalars = RigidArray<Unicode.Scalar>(capacity: utf8Bytes.count)
        self.decode(utf8Bytes: utf8Bytes, errors: &errors)
    }

    /// Decodes the given UTF-8 bytes into Unicode scalars.
    @usableFromInline
    mutating func decode(
        utf8Bytes: Span<UInt8>,
        errors: inout IDNA.MappingErrors
    ) {
        self.scalars.edit { output in
            var unicodeScalarsIterator = UnicodeScalarIterator()
            while let uncheckedScalar = unicodeScalarsIterator.next(in: utf8Bytes) {
                guard let scalar = Unicode.Scalar(uncheckedScalar) else {
                    /// This type is to use in punycode-encode func so we preemptively assume that.
                    errors.append(
                        .labelPunycodeEncodeFailed(
                            label: String(span: utf8Bytes)
                        )
                    )
                    /// Error already appended in mapToIDNAMappings
                    continue
                }
                output.append(scalar)
            }
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension DecodedUnicodeScalars {
    /// A subsequence of a `DecodedUnicodeScalars` container.
    /// This is tuned to this library's needs so it might need some adjustments for other use cases.
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

        /// Set the range of the subsequence to the given range of bytes.
        /// This function will translate the `utf8OffsetRange` to the range of scalars.
        ///
        /// As an optimization, this function assumes the new range is after the last range it was set to.
        /// As always, tests will catch the issue if it's not the case.
        @inlinable
        mutating func set(utf8OffsetRange range: Range<Int>) {
            let scalarsCount = self.scalars.count
            var byteOffset = self.endIndexByteOffset

            if range.lowerBound == 0 {
                self.startIndex = 0
            } else {
                var idx = self.endIndex
                while idx < scalarsCount {
                    let scalar = unsafe self.scalars[unchecked: idx]
                    byteOffset &+= scalar.utf8.count
                    if byteOffset == range.lowerBound {
                        self.startIndex = idx &+ 1
                        break
                    }
                    idx &+= 1
                }
            }

            var idx = self.startIndex
            while idx < scalarsCount {
                let scalar = unsafe self.scalars[unchecked: idx]
                byteOffset &+= scalar.utf8.count
                if byteOffset == range.upperBound {
                    self.endIndex = idx &+ 1
                    self.endIndexByteOffset = byteOffset
                    break
                }
                idx &+= 1
            }
        }

        /// Returns the unicode scalar at the given index.
        @inlinable
        subscript(index: Int) -> Unicode.Scalar {
            /// This assert is to trap in tests for the most part.
            /// That's why it's not a precondition.
            assert(self.endIndex > index, "Index out of bounds")
            return unsafe self.scalars[unchecked: self.startIndex &+ index]
        }
    }
}
