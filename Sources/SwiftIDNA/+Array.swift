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

extension Array where Element == UInt8 {
    var _swift_idna_debugDescription: String {
        #if $Embedded
        "[(cannot print array values in embedded Swift)]"
        #else
        self.debugDescription
        #endif
    }
}
