@available(swiftIDNAApplePlatforms 10.15, *)
extension String {
    @inlinable
    var nfcCodePoints: [UInt8] {
        var codePoints = [UInt8]()
        codePoints.reserveCapacity(self.utf8.count)
        self._withNFCCodeUnits {
            codePoints.append($0)
        }
        return codePoints
    }

    @inlinable
    var asNFC: String {
        String(
            unsafeUninitializedCapacity_Compatibility: self.utf8.count
        ) { appendFunction in
            self._withNFCCodeUnits {
                appendFunction($0)
            }
        }
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    @inlinable
    var isInNFC_slow: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @inline(__always)
    @usableFromInline
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        if #available(swiftIDNAApplePlatforms 11, *) {
            self.init(unsafeUninitializedCapacity: span.count) { stringBuffer in
                let rawStringBuffer = UnsafeMutableRawBufferPointer(stringBuffer)
                span.withUnsafeBytes { spanPtr in
                    rawStringBuffer.copyMemory(from: spanPtr)
                }
                return span.count
            }
        } else {
            var string = ""
            string.reserveCapacity(span.count)
            span.withUnsafeBytes { spanPtr in
                for idx in spanPtr.indices {
                    string.append(String(UnicodeScalar(spanPtr[idx])))
                }
            }
            self = string
        }
    }

    @inline(__always)
    @usableFromInline
    mutating func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try body(self.utf8Span.span)
        }
        do {
            return try self.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }

    @inline(__always)
    @usableFromInline
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingWith initializer: (
            _ appendFunction: (UInt8) -> Void
        ) throws -> Void
    ) rethrows {
        if #available(swiftIDNAApplePlatforms 11, *) {
            try self.init(unsafeUninitializedCapacity: capacity) { stringBuffer in
                var idx = 0
                try initializer {
                    stringBuffer[idx] = $0
                    idx &+= 1
                }
                return idx
            }
        } else {
            var string = ""
            string.reserveCapacity(capacity)
            try initializer {
                string.append(String(UnicodeScalar($0)))
            }
            self = string
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension Substring {
    @inline(__always)
    @usableFromInline
    mutating func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try body(self.utf8Span.span)
        }
        do {
            return try self.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }
}
