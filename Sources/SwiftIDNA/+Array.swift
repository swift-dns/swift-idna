@available(swiftIDNAApplePlatforms 13, *)
extension [UInt8] {
    @inlinable
    mutating func append(span: Span<UInt8>) {
        guard span.count > 0 else {
            return
        }
        self.reserveCapacity(span.count)
        for idx in span.indices {
            self.append(span[unchecked: idx])
        }
        // self.withUnsafeMutableBytes { buffer in
        //     span.withUnsafeBytes { spanPtr in
        //         buffer.baseAddress.unsafelyUnwrapped.copyMemory(
        //             from: spanPtr.baseAddress.unsafelyUnwrapped,
        //             byteCount: span.count
        //         )
        //     }
        // }
    }
}
