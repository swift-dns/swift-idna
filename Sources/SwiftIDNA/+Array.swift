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
        /// At most 3 digits per byte, 2 bytes for each of the `count - 1` separators, 2 for the brackets.
        var description = ""
        description.reserveCapacity(self.count &* 5)
        description += "["
        var isFirst = true
        for byte in self {
            if isFirst {
                isFirst = false
            } else {
                description += ", "
            }
            description += "\(byte)"
        }
        description += "]"
        return description
    }
}
