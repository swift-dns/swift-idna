@available(swiftIDNAApplePlatforms 26, *)
struct MacOS26CompatibilityHelper: CompatibilityHelper {
    @inlinable
    func makeString(
        unsafeUninitializedCapacity capacity: Int,
        initializingWith initializer: (
            _ appendFunction: (UInt8) -> Void
        ) throws -> Void
    ) rethrows -> String {
        try String(unsafeUninitializedCapacity: capacity) { stringBuffer in
            var idx = 0
            try initializer {
                stringBuffer[idx] = $0
                idx &+= 1
            }
            return idx
        }
    }

    @inlinable
    func makeString(_uncheckedAssumingValidUTF8 span: Span<UInt8>) -> String {
        String(unsafeUninitializedCapacity: span.count) { stringBuffer in
            let rawStringBuffer = UnsafeMutableRawBufferPointer(stringBuffer)
            span.withUnsafeBytes { spanPtr in
                rawStringBuffer.copyMemory(from: spanPtr)
            }
            return span.count
        }
    }

    @inlinable
    func withSpan<T>(
        for bytes: [UInt8],
        _ body: (Span<UInt8>) throws -> T
    ) rethrows -> T {
        try body(bytes.span)
    }

    @inlinable
    func withSpan<T, E: Error>(
        for string: inout String,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        try body(string.utf8Span.span)
    }

    @inlinable
    func withSpan<T, E: Error>(
        for substring: inout Substring,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        try body(substring.utf8Span.span)
    }

    @inlinable
    func isInNFC(span: Span<UInt8>) -> Bool {
        var utf8Span = UTF8Span(unchecked: span)
        return utf8Span.checkForNFC(quickCheck: false)
    }

    @inlinable
    func _uncheckedAssumingValidUTF8_ensureNFC(on bytes: inout [UInt8]) {
        var utf8Span = UTF8Span(unchecked: bytes.span)
        if !utf8Span.checkForNFC(quickCheck: false) {
            bytes = self.makeString(_uncheckedAssumingValidUTF8: bytes.span).nfcCodePoints
        }
    }

    @_lifetime(copy span)
    @inlinable
    func makeUnicodeScalarIterator(
        of span: Span<UInt8>
    ) -> any UnicodeScalarsIteratorProtocol & ~Escapable {
        let utf8Span = UTF8Span(unchecked: span)
        let iterator = _overrideLifetime(
            utf8Span.makeUnicodeScalarIterator(),
            copying: self
        )
        return iterator
    }
}
