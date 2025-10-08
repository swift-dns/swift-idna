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
    }

    borrowing func withSpan_Compatibility<T>(
        _ body: (Span<UInt8>) -> T
    ) -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return body(self.span)
        }
        return self.withUnsafeBufferPointer { bytesPtr in
            body(bytesPtr.span)
        }
    }

    mutating func uncheckedUTF8Bytes_ensureNFC() {
        self.withSpan_Compatibility { span in
            if #available(swiftIDNAApplePlatforms 26, *) {
                var utf8Span = UTF8Span(unchecked: span)
                if !utf8Span.checkForNFC(quickCheck: false) {
                    self = String(uncheckedUTF8Span: span).nfcCodePoints
                }
                return
            }
            let string = String(uncheckedUTF8Span: span)
            if !string.isInNFC_slow {
                self = string.nfcCodePoints
            }
        }
    }
}
