public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
extension UniqueArray<UInt8> {
    @usableFromInline
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        if self.isEmpty || self.span.isASCII { return }

        let string = String(_uncheckedAssumingValidUTF8: self.span)

        self.removeAll(keepingCapacity: true)
        self.edit { output in
            string._withNFCCodeUnits { utf8Byte in
                output.append(utf8Byte)
            }
        }
    }
}
