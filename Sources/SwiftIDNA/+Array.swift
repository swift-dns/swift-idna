@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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
        _ body: (Span<UInt8>) throws -> T
    ) rethrows -> T {
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            return try body(self.span)
        }
        return try self.withUnsafeBufferPointer { bytesPtr in
            try body(bytesPtr.span)
        }
    }

    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        self.withSpan_Compatibility { span in
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
                var utf8Span = UTF8Span(unchecked: span)
                if !utf8Span.checkForNFC(quickCheck: false) {
                    self = String(_uncheckedAssumingValidUTF8: span).nfcCodePoints
                }
                return
            }
            let string = String(_uncheckedAssumingValidUTF8: span)
            if !string.isInNFC_slow {
                self = string.nfcCodePoints
            }
        }
    }
}
