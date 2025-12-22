@available(swiftIDNAApplePlatforms 10.15, *)
extension [UInt8] {
    @inlinable
    var isASCII: Bool {
        var result: UInt8 = 0
        for byte in self {
            result |= byte
        }
        return result <= 0x7F
    }

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

    @usableFromInline
    borrowing func withSpan_Compatibility<T>(
        _ body: (Span<UInt8>) throws -> T
    ) rethrows -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try body(self.span)
        }
        return try self.withUnsafeBufferPointer { bytesPtr in
            try body(bytesPtr.span)
        }
    }

    @usableFromInline
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        self.withSpan_Compatibility { span in
            if #available(swiftIDNAApplePlatforms 26, *) {
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

@available(swiftIDNAApplePlatforms 10.15, *)
extension [UInt8].SubSequence {
    @inlinable
    var isASCII: Bool {
        var result: UInt8 = 0
        for byte in self {
            result |= byte
        }
        return result <= 0x7F
    }

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
}
