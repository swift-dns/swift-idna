@available(swiftIDNAApplePlatforms 13, *)
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
        String(unsafeUninitializedCapacity: self.utf8.count) { stringBuffer in
            var idx = 0
            self._withNFCCodeUnits {
                stringBuffer[idx] = $0
                idx &+= 1
            }
            return idx
        }
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    var isInNFC_slow: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @_lifetime(copy span)
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        self.init(unsafeUninitializedCapacity: span.count) { stringBuffer in
            let rawStringBuffer = UnsafeMutableRawBufferPointer(stringBuffer)
            span.withUnsafeBytes { spanPtr in
                rawStringBuffer.copyMemory(from: spanPtr)
            }
            return span.count
        }
    }

    mutating func withSpan_Compatibility_macOSUnder26<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
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

@available(swiftIDNAApplePlatforms 13, *)
extension Substring {
    mutating func withSpan_Compatibility_macOSUnder26<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
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
