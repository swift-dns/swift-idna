@available(SwiftStdlib 5.1, *)
extension Span<UInt8> {
    /// Whether or not the span contains only ASCII bytes.
    @inlinable
    var isASCII: Bool {
        var result: Element = 0
        /// This loop is usually auto-vectorized into SIMD instructions by LLVM.
        for idx in self.indices {
            result |= self[idx]
        }
        return result <= 0x7F
    }

    /// Whether or not the span scalars are all in Normalization Form C (NFC).
    @inlinable
    var isInNFC: Bool {
        if NFCNormalization.quickCheck(self) {
            return true
        }
        return NFCNormalization.withNFCNormalized(self) { normalizedSpan in
            if normalizedSpan.count != self.count {
                return false
            }
            for idx in self.indices {
                if unsafe normalizedSpan[unchecked: idx] != self[idx] {
                    return false
                }
            }
            return true
        }
    }

    /// Checks if contains any labels that start with “xn--”
    @inlinable
    var containsIDNADomainNameMarkerLabelPrefix: Bool {
        if self.count >= 4 {
            if self[0] == UInt8.asciiLowercasedX,
                self[1] == UInt8.asciiLowercasedN,
                self[2] == UInt8.asciiHyphenMinus,
                self[3] == UInt8.asciiHyphenMinus
            {
                return true
            }
        } else {
            /// Not enough elements
            return false
        }

        /// Did not start with “xn--”, check the rest of the labels

        return self.containsAnyIDNADomainNameMarkerLabelPrefix { idxOfX in
            /// Count behind the "x" in a "xn--"
            let countBehindX = idxOfX

            /// See if there is a label separator before this "xn--"
            switch countBehindX {
            case 0:
                /// The whole domain starts with "xn--"
                return true
            case 1, 2:
                let before = unsafe self[unchecked: idxOfX &- 1]
                if before.isIDNALabelSeparator {
                    return true
                }
            case 3...:
                let third = unsafe self[unchecked: idxOfX &- 1]
                if third.isIDNALabelSeparator {
                    return true
                }
                let second = unsafe self[unchecked: idxOfX &- 2]
                let first = unsafe self[unchecked: idxOfX &- 3]
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
            if unsafe self[unchecked: idx] == UInt8.asciiLowercasedX,
                unsafe self[unchecked: idx + 1] == UInt8.asciiLowercasedN,
                unsafe self[unchecked: idx + 2] == UInt8.asciiHyphenMinus,
                unsafe self[unchecked: idx + 3] == UInt8.asciiHyphenMinus
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

        if self[0] == UInt8.asciiLowercasedX,
            self[1] == UInt8.asciiLowercasedN,
            self[2] == UInt8.asciiHyphenMinus,
            self[3] == UInt8.asciiHyphenMinus
        {
            return true
        } else {
            return false
        }
    }

    /// Returns true if the span contains only valid UTF-8 bytes.
    @inlinable
    func checkUTF8() -> Bool {
        if self.isASCII {
            return true
        }

        var seenInvalidUTF8 = false

        SIMDUnicodeScalarDecoder.withTemporaryDecoder { decoder in
            /// Process windows of size `SIMDUnicodeScalarDecoder.windowSize`, one by one.
            var startIdx = 0
            outerLoop: while startIdx < count {
                decoder.decodeNextWindow(of: self, startIdx: startIdx)
                let scalarCount = decoder.scalarCount

                var scalarIdx = 0
                while scalarIdx < scalarCount {
                    let offset = decoder.scalarStartOffset(at: scalarIdx)
                    let uncheckedScalar = unsafe decoder.uncheckedScalarValues[unchecked: offset]

                    if Unicode.Scalar(uncheckedScalar) == nil {
                        seenInvalidUTF8 = true
                        break outerLoop
                    }

                    scalarIdx &+= 1
                }

                startIdx &+= decoder.windowEndOffset()
            }
        }

        return !seenInvalidUTF8
    }
}

@available(SwiftStdlib 5.1, *)
extension Span {
    /// Finds the last index of the given element in the span.
    @inlinable
    func lastIndex(of element: Element) -> Int? where Element: Equatable {
        let endIndex = self.count &- 1
        for idx in self.indices {
            let backwardsIdx = endIndex &- idx
            if unsafe self[unchecked: backwardsIdx] == element {
                return backwardsIdx
            }
        }
        return nil
    }
}
