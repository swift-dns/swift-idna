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
        globalCompatibilityHelper.makeString(
            unsafeUninitializedCapacity: self.utf8.count
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
}
