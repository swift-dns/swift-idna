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
}
