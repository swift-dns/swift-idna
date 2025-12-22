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

@available(swiftIDNAApplePlatforms 10.15, *)
extension Array {
    @inlinable
    init(copying span: Span<Element>) {
        self.init(unsafeUninitializedCapacity: span.count) { buffer, initializedCount in
            for idx in 0..<span.count {
                buffer[idx] = span[unchecked: idx]
            }
            initializedCount = span.count
        }
    }
}
