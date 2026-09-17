@available(SwiftStdlib 5.1, *)
extension OutputSpan<UInt8> {
    /// Appends the given span to the output span.
    @inlinable
    mutating func swift_idna_append(copying span: Span<UInt8>) {
        let appendCount = span.count
        if appendCount == 0 { return }
        let usedCapacity = self.count
        unsafe self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let target = unsafe UnsafeMutableRawPointer(
                    buffer.baseAddress.unsafelyUnwrapped
                ).advanced(by: usedCapacity)
                unsafe target.copyMemory(
                    from: spanPtr.baseAddress.unsafelyUnwrapped,
                    byteCount: appendCount
                )
            }
            initializedCount = usedCapacity &+ appendCount
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension OutputSpan where Element: BinaryInteger {
    /// Inserts the given element at the given index into the output span.
    @inlinable
    mutating func swift_idna_insert(_ element: Element, at index: Int) {
        let usedCapacity = self.count
        unsafe self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            if index < usedCapacity {
                let sourceRange = unsafe Range<Int>(uncheckedBounds: (index, usedCapacity))
                let source = buffer.extracting(sourceRange)
                let targetRange = unsafe Range<Int>(
                    uncheckedBounds: (index &+ 1, usedCapacity &+ 1)
                )
                let target = buffer.extracting(targetRange)
                let last = unsafe target.moveInitialize(fromContentsOf: source)
                assert(last == target.endIndex)
            }
            unsafe buffer.initializeElement(at: index, to: element)
            initializedCount = usedCapacity &+ 1
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension OutputSpan<UInt8> {
    /// Appends the significant bytes of an encoded Unicode scalar to the output span, possibly speculatively.
    @inlinable
    mutating func swift_idna_append(
        encodedScalar bytes: (UInt8, UInt8, UInt8, UInt8),
        count: Int
    ) {
        assert(count >= 1 && count <= 4)
        unsafe self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            let idx = initializedCount
            if idx &+ 4 <= buffer.count {
                unsafe buffer[idx] = bytes.0
                unsafe buffer[idx &+ 1] = bytes.1
                unsafe buffer[idx &+ 2] = bytes.2
                unsafe buffer[idx &+ 3] = bytes.3
            } else {
                unsafe buffer[idx] = bytes.0
                if count > 1 { unsafe buffer[idx &+ 1] = bytes.1 }
                if count > 2 { unsafe buffer[idx &+ 2] = bytes.2 }
                if count > 3 { unsafe buffer[idx &+ 3] = bytes.3 }
            }
            initializedCount &+= count
        }
    }
}
