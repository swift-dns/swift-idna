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

    var isInNFC: Bool {
        if #available(swiftIDNAApplePlatforms 26, *) {
            var utf8Span = self.utf8Span
            return utf8Span.checkForNFC(quickCheck: false)
        }
        return self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @available(swiftIDNAApplePlatforms 13, *)
    @_lifetime(borrow span)
    init(uncheckedUTF8Span span: Span<UInt8>) {
        let count = span.count
        self.init(unsafeUninitializedCapacity: count) { stringBuffer in
            let rawStringBuffer = UnsafeMutableRawBufferPointer(stringBuffer)
            span.withUnsafeBytes { spanPtr in
                rawStringBuffer.copyMemory(from: spanPtr)
            }
            return count
        }
    }
}
