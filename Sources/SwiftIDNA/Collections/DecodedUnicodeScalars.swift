public import BasicContainers

/// A container that holds a group of decoded Unicode scalars.
@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct DecodedUnicodeScalars: ~Copyable {
    @usableFromInline
    var scalars: RigidArray<UnicodeScalarValue>

    @inlinable
    package init(utf8Bytes: Span<UInt8>, errors: inout IDNA.MappingErrors) {
        self.scalars = RigidArray<UnicodeScalarValue>(capacity: utf8Bytes.count)
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
                guard let scalar = UnicodeScalarValue(uncheckedScalar) else {
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
    package struct Subsequence: ~Copyable, ~Escapable {
        @usableFromInline
        var scalars: Span<UnicodeScalarValue>
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
        package init(base: inout DecodedUnicodeScalars) {
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
        package mutating func set(utf8OffsetRange range: Range<Int>) {
            let scalarsCount = self.scalars.count
            var byteOffset = self.endIndexByteOffset

            if range.lowerBound == 0 {
                self.startIndex = 0
            } else {
                var idx = self.endIndex
                while idx < scalarsCount {
                    let scalar = unsafe self.scalars[unchecked: idx]
                    byteOffset &+= UTF8BytesIterator.utf8Length(uncheckedScalar: scalar.value)
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
                byteOffset &+= UTF8BytesIterator.utf8Length(uncheckedScalar: scalar.value)
                if byteOffset == range.upperBound {
                    self.endIndex = idx &+ 1
                    self.endIndexByteOffset = byteOffset
                    break
                }
                idx &+= 1
            }
        }

        /// Runs `body` over the subsequence's scalar values as raw `UInt32`s.
        ///
        /// `UnicodeScalarValue` is `@frozen` around a single `UInt32`, so the rebind is a
        /// reinterpretation of identical storage, not a conversion.
        @inlinable
        func withUnsafeScalarValues<R>(_ body: (UnsafePointer<UInt32>) -> R) -> R? {
            self.scalars.withUnsafeBufferPointer { buffer -> R? in
                guard let base = buffer.baseAddress else {
                    return nil
                }
                return unsafe base.withMemoryRebound(
                    to: UInt32.self,
                    capacity: buffer.count
                ) { values -> R? in
                    unsafe body(values + self.startIndex)
                }
            }
        }

        /// Returns the unicode scalar at the given index.
        @inlinable
        subscript(index: Int) -> UnicodeScalarValue {
            /// This assert is to trap in tests for the most part.
            /// That's why it's not a precondition.
            assert(self.endIndex > index, "Index out of bounds")
            return unsafe self.scalars[unchecked: self.startIndex &+ index]
        }
    }
}
