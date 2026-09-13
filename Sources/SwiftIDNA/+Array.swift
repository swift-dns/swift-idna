@available(SwiftStdlib 5.1, *)
extension Array where Element: BitwiseCopyable {
    /// Initializes an `Array` by copying the given span.
    @inlinable
    package init(copying span: Span<Element>) {
        unsafe self.init(unsafeUninitializedCapacity: span.count) { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                unsafe rawBuffer.copyMemory(from: spanPtr)
            }
            initializedCount = span.count
        }
    }
}
