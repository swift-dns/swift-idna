@available(swiftIDNAApplePlatforms 10.15, *)
extension Array where Element: BitwiseCopyable {
    @inlinable
    init(copying span: Span<Element>) {
        self.init(unsafeUninitializedCapacity: span.count) { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.copyMemory(from: spanPtr)
            }
            initializedCount = span.count
        }
    }
}
