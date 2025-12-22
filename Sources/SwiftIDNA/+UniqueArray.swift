public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
extension UniqueArray<UInt8> {
    @usableFromInline
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        if #available(swiftIDNAApplePlatforms 26, *) {
            var utf8Span = UTF8Span(unchecked: self.span)
            if !utf8Span.checkForNFC(quickCheck: false) {
                self = String(_uncheckedAssumingValidUTF8: self.span).nfcCodePoints
            }
            return
        }
        var string = String(_uncheckedAssumingValidUTF8: self.span)
        if !string.isInNFC_slow {
            self = string.nfcCodePoints
        }
    }
}
