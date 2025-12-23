@available(swiftIDNAApplePlatforms 10.15, *)
extension [UInt8] {
    @inlinable
    init(copying span: Span<UInt8>) {
        self.init(unsafeUninitializedCapacity: span.count) { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.copyMemory(from: spanPtr)
            }
            initializedCount = span.count
        }
    }
}
