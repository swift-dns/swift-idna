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

    @inlinable
    borrowing func withSpan_Compatibility<T>(
        _ body: (Span<UInt8>) -> T
    ) -> T {
        self.withUnsafeBufferPointer { bytesPtr in
            body(bytesPtr.span)
        }
    }

    func makeNFCIfNeeded_assumingSelfIsUTF8() -> [UInt8] {
        self.withSpan_Compatibility { span in
            if #available(swiftIDNAApplePlatforms 26, *) {
                var utf8Span = UTF8Span(unchecked: span)
                if utf8Span.checkForNFC(quickCheck: false) {
                    return self
                } else {
                    return String(uncheckedUTF8Span: span).nfcCodePoints
                }
            }
            let string = String(uncheckedUTF8Span: span)
            if string.isInNFC_slow {
                return string.nfcCodePoints
            } else {
                return self
            }
        }
    }
}
