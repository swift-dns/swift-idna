@available(swiftIDNAApplePlatforms 10.15, *)
extension String {
    var nfcCodePoints: [UInt8] {
        var codePoints = [UInt8]()
        codePoints.reserveCapacity(self.utf8.count)
        self._withNFCCodeUnits {
            codePoints.append($0)
        }
        return codePoints
    }

    var asNFC: String {
        String(
            unsafeUninitializedCapacity_Compatibility: self.utf8.count
        ) { outputSpan in
            self._withNFCCodeUnits {
                outputSpan.append($0)
            }
        }
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    var isInNFC_slow: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @inline(__always)
    @inlinable
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        self.init(unsafeUninitializedCapacity_Compatibility: span.count) { outputSpan in
            span.withUnsafeBytes { spanPtr in
                outputSpan.withUnsafeMutableBufferPointer { (outputSpanPtr, initializedCount) in
                    let rawPointer = UnsafeMutableRawBufferPointer(outputSpanPtr)
                    rawPointer.copyMemory(from: spanPtr)
                    initializedCount = span.count
                }
            }
        }
    }

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
        initializingWith initializer: (_ handle: inout OutputSpan<UInt8>) throws -> Void
    ) rethrows {
        if #available(swiftIDNAApplePlatforms 11, *) {
            try self.init(unsafeUninitializedCapacity: capacity) { stringBuffer in
                var span = OutputSpan(buffer: stringBuffer, initializedCount: 0)
                try initializer(&span)
                return span.count
            }
        } else {
            let array = try [UInt8].init(
                unsafeUninitializedCapacity: capacity
            ) { buffer, initializedCount in
                var span = OutputSpan(buffer: buffer, initializedCount: 0)
                try initializer(&span)
                initializedCount = span.count
            }
            self = String(decoding: array, as: Unicode.UTF8.self)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension Substring {
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
