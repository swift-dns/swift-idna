@available(swiftIDNAApplePlatforms 10.15, *)
extension Span<UInt8> {
    @inlinable
    var isASCII: Bool {
        var result: Element = 0
        for idx in self.indices {
            result |= self[unchecked: idx]
        }
        return result <= 0x7F
    }

    @usableFromInline
    var isInNFC: Bool {
        if self.isEmpty || self.isASCII { return true }
        let string = String(_uncheckedAssumingValidUTF8: self)
        return string.isEqualToNFCCodePointsOfSelf()
    }

    @usableFromInline
    @inline(__always)
    @_lifetime(copy self)
    func makeUnicodeScalarIterator_Compatibility() -> (
        any UnicodeScalarsIteratorProtocol & ~Escapable
    ) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            let utf8Span = UTF8Span(unchecked: self)
            return utf8Span.makeUnicodeScalarIterator()
        }
        let iterator = String(_uncheckedAssumingValidUTF8: self).unicodeScalars.makeIterator()
        return UnicodeScalarViewCompatibilityIterator(
            underlyingIterator: iterator,
            currentCodeUnitOffset: 0
        )
    }

    /// Checks if contains any labels that start with “xn--”
    @inlinable
    var containsIDNADomainNameMarkerLabelPrefix: Bool {
        if self.count >= 4 {
            if self[unchecked: 0] == UInt8.asciiLowercasedX,
                self[unchecked: 1] == UInt8.asciiLowercasedN,
                self[unchecked: 2] == UInt8.asciiHyphenMinus,
                self[unchecked: 3] == UInt8.asciiHyphenMinus
            {
                return true
            }
        } else {
            /// Not enough elements
            return false
        }

        /// Did not start with “xn--”, check the rest of the labels

        return self.containsAnyIDNADomainNameMarkerLabelPrefix { idxOfX in
            let countBehindX = idxOfX

            /// See if there is a label separator before this "xn--"
            switch countBehindX {
            case 0:
                /// The whole domain starts with "xn--"
                return true
            case 1, 2:
                let before = self[unchecked: idxOfX &- 1]
                if before.isIDNALabelSeparator {
                    return true
                }
            case 3...:
                let third = self[unchecked: idxOfX &- 1]
                if third.isIDNALabelSeparator {
                    return true
                }
                let second = self[unchecked: idxOfX &- 2]
                let first = self[unchecked: idxOfX &- 3]
                if Span<UInt8>.isIDNALabelSeparator(first, second, third) {
                    return true
                }
            default:
                break
            }

            return false
        }
    }

    /// Finds all "xn--"s, feeds them to the closure.
    /// Returns true if any of the closure calls return true.
    @inlinable
    func containsAnyIDNADomainNameMarkerLabelPrefix(
        /// firstMarkerIndex == index of the "x" in a "xn--"
        where predicate: (_ firstMarkerIndex: Int) -> Bool
    ) -> Bool {
        for idx in self.indices.dropLast(3) {
            if self[unchecked: idx] == UInt8.asciiLowercasedX,
                self[unchecked: idx + 1] == UInt8.asciiLowercasedN,
                self[unchecked: idx + 2] == UInt8.asciiHyphenMinus,
                self[unchecked: idx + 3] == UInt8.asciiHyphenMinus
            {
                if predicate(idx) {
                    return true
                }
            }
        }

        return false
    }

    /// There are 4 IDNA label separators, 1 of which is `.`, which is only 1 byte.
    /// The other 3 are the ones in this function.
    /// This function doesn't try to detect `.`.
    @inlinable
    static func isIDNALabelSeparator(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> Bool {
        /// U+3002 ( 。 ) IDEOGRAPHIC FULL STOP
        if first == 227, second == 128, third == 130 {
            return true
        }
        /// U+FF0E ( ． ) FULLWIDTH FULL STOP
        if first == 239, second == 188, third == 142 {
            return true
        }
        /// U+FF61 ( ｡ ) HALFWIDTH IDEOGRAPHIC FULL STOP
        if first == 239, second == 189, third == 161 {
            return true
        }
        return false
    }

    /// Checks if the label starts with “xn--”
    @inlinable
    var hasIDNADomainNameMarkerPrefix: Bool {
        guard self.count >= 4 else {
            return false
        }

        if self[unchecked: 0] == UInt8.asciiLowercasedX,
            self[unchecked: 1] == UInt8.asciiLowercasedN,
            self[unchecked: 2] == UInt8.asciiHyphenMinus,
            self[unchecked: 3] == UInt8.asciiHyphenMinus
        {
            return true
        } else {
            return false
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension Span {
    @inlinable
    func allSatisfy(_ predicate: (Element) -> Bool) -> Bool {
        for idx in self.indices {
            if !predicate(self[unchecked: idx]) {
                return false
            }
        }
        return true
    }

    @inlinable
    func lastIndex(of element: Element) -> Int? where Element: Equatable {
        let endIndex = self.count &- 1
        for idx in self.indices {
            let backwardsIdx = endIndex &- idx
            if self[unchecked: backwardsIdx] == element {
                return backwardsIdx
            }
        }
        return nil
    }
}
