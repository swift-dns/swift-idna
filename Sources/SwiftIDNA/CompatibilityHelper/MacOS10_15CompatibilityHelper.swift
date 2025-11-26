@available(swiftIDNAApplePlatforms 10.15, *)
struct MacOS10_15CompatibilityHelper: CompatibilityHelper {
    @inlinable
    func makeString(
        unsafeUninitializedCapacity capacity: Int,
        initializingWith initializer: (
            _ appendFunction: (UInt8) -> Void
        ) throws -> Void
    ) rethrows -> String {
        var string = ""
        string.reserveCapacity(capacity)
        try initializer {
            string.append(String(UnicodeScalar($0)))
        }
        return string
    }

    @inlinable
    func makeString(_uncheckedAssumingValidUTF8 span: Span<UInt8>) -> String {
        var string = ""
        string.reserveCapacity(span.count)
        span.withUnsafeBytes { spanPtr in
            for idx in spanPtr.indices {
                string.append(String(UnicodeScalar(spanPtr[idx])))
            }
        }
        return string
    }

    @inlinable
    func withSpan<T>(
        for bytes: [UInt8],
        _ body: (Span<UInt8>) throws -> T
    ) rethrows -> T {
        try bytes.withUnsafeBufferPointer { bytesPtr in
            try body(bytesPtr.span)
        }
    }

    @inlinable
    func withSpan<T, E: Error>(
        for string: inout String,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        do {
            return try string.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }

    @inlinable
    func withSpan<T, E: Error>(
        for substring: inout Substring,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        do {
            return try substring.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }

    @inlinable
    func isInNFC(span: Span<UInt8>) -> Bool {
        self.makeString(_uncheckedAssumingValidUTF8: span).isInNFC_slow
    }

    @inlinable
    func _uncheckedAssumingValidUTF8_ensureNFC(on bytes: inout [UInt8]) {
        self.withSpan(for: bytes) { bytesSpan in
            let string = self.makeString(_uncheckedAssumingValidUTF8: bytesSpan)
            if !string.isInNFC_slow {
                bytes = string.nfcCodePoints
            }
        }
    }

    @_lifetime(copy span)
    @inlinable
    func makeUnicodeScalarIterator(
        of span: Span<UInt8>
    ) -> any UnicodeScalarsIteratorProtocol & ~Escapable {
        let iterator =
            self
            .makeString(_uncheckedAssumingValidUTF8: span)
            .unicodeScalars
            .makeIterator()
        return UnicodeScalarViewCompatibilityIterator(
            underlyingIterator: iterator,
            currentCodeUnitOffset: 0
        )
    }
}
