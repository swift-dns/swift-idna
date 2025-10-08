/// TODO: Use `UTF8Span.checkForNFC(quickCheck: false)` instead of this.
/// That would require macos 26 unfortunately.
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
            decoding: self.nfcCodePoints,
            as: UTF8.self
        )
    }

    var isInNFC: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
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
