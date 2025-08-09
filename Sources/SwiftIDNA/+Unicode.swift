extension UnicodeScalar {
    /// Turns the character into a lowercased ASCII letter only if it's an uppercased ASCII letter.
    @inlinable
    public func toLowercasedASCIILetter() -> Self {
        if self.isUppercasedASCIILetter {
            /// https://ss64.com/ascii.html
            /// The difference between an upper and lower cased ASCII byte is their sixth bit.
            /// Turn the sixth bit on to ensure lowercased ASCII byte.
            return Self(self.value | 0b0010_0000).unsafelyUnwrapped
        } else {
            return self
        }
    }

    /// Turns the character into a lowercased ASCII letter only if it's an uppercased ASCII letter.
    /// Does not check if the value is an uppercased ASCII letter.
    @inlinable
    public func uncheckedToLowercasedASCIILetter() -> Self {
        /// https://ss64.com/ascii.html
        /// The difference between an upper and lower cased ASCII byte is their sixth bit.
        /// Turn the sixth bit on to ensure lowercased ASCII byte.
        Self(self.value | 0b0010_0000)!
    }

    @inlinable
    public var isUppercasedASCIILetter: Bool {
        self.value >= 0x41 && self.value <= 0x5A
    }

    /// Returns if the character is an IDNA label separator, like `.` in `mahdibm.com`.
    /// U+002E ( . ) FULL STOP
    /// U+FF0E ( ． ) FULLWIDTH FULL STOP
    /// U+3002 ( 。 ) IDEOGRAPHIC FULL STOP
    /// U+FF61 ( ｡ ) HALFWIDTH IDEOGRAPHIC FULL STOP
    /// https://www.unicode.org/reports/tr46/#Notation
    @inlinable
    public var isIDNALabelSeparator: Bool {
        self.value == 0x2E
            || self.value == 0xFF0E
            || self.value == 0x3002
            || self.value == 0xFF61
    }
}

extension Unicode.Scalar {
    @inlinable
    var isNumberOrLowercasedLetterOrHyphenMinusASCII: Bool {
        (self.value >= 0x30 && self.value <= 0x39)
            || (self.value >= 0x61 && self.value <= 0x7A)
            || self.isHyphenMinus
    }

    @inlinable
    var isNumberOrLowercasedLetterOrDotASCII: Bool {
        (self.value >= 0x30 && self.value <= 0x39)
            || (self.value >= 0x61 && self.value <= 0x7A)
            || self.isASCIIDot
    }

    @inlinable
    static var asciiHyphenMinus: Unicode.Scalar {
        Unicode.Scalar(0x2D).unsafelyUnwrapped
    }

    @inlinable
    var isHyphenMinus: Bool {
        self.value == 0x2D
    }

    @inlinable
    static var asciiDot: Unicode.Scalar {
        Unicode.Scalar(0x2E).unsafelyUnwrapped
    }

    @inlinable
    var isASCIIDot: Bool {
        self.value == 0x2E
    }

    @inlinable
    static var asciiLowercasedX: Unicode.Scalar {
        Unicode.Scalar(0x78).unsafelyUnwrapped
    }

    @inlinable
    static var asciiLowercasedN: Unicode.Scalar {
        Unicode.Scalar(0x6E).unsafelyUnwrapped
    }
}

extension Unicode.GeneralCategory {
    @inlinable
    var isMark: Bool {
        switch self {
        case .spacingMark, .enclosingMark, .nonspacingMark:
            return true
        default:
            return false
        }
    }
}

extension Collection<Unicode.Scalar> {
    /// Checks if contains any labels that start with “xn--”
    @inlinable
    var containsIDNADomainNameMarkerLabelPrefix: Bool {
        if let lastMarkerIdx = self.index(self.startIndex, offsetBy: 3, limitedBy: self.endIndex) {
            if self[self.startIndex] == Unicode.Scalar.asciiLowercasedX,
                self[self.index(self.startIndex, offsetBy: 1)] == Unicode.Scalar.asciiLowercasedN,
                self[self.index(self.startIndex, offsetBy: 2)] == Unicode.Scalar.asciiHyphenMinus,
                self[lastMarkerIdx] == Unicode.Scalar.asciiHyphenMinus
            {
                return true
            }
        } else {
            /// Not enough elements
            return false
        }

        /// Did not start with “xn--”, check the rest of the labels

        var startIndex = self.startIndex

        while let separatorIdx = self[startIndex...].firstIndex(where: \.isIDNALabelSeparator) {
            if let lastMarkerIdx = self.index(separatorIdx, offsetBy: 4, limitedBy: self.endIndex) {
                startIndex = self.index(separatorIdx, offsetBy: 1)

                if self[self.index(separatorIdx, offsetBy: 1)] == Unicode.Scalar.asciiLowercasedX,
                    self[self.index(separatorIdx, offsetBy: 2)] == Unicode.Scalar.asciiLowercasedN,
                    self[self.index(separatorIdx, offsetBy: 3)] == Unicode.Scalar.asciiHyphenMinus,
                    self[lastMarkerIdx] == Unicode.Scalar.asciiHyphenMinus
                {
                    return true
                }

            } else {
                /// Not enough elements
                return false
            }
        }

        return false
    }

    /// Checks if the label starts with “xn--”
    @inlinable
    var hasIDNADomainNameMarkerPrefix: Bool {
        if let lastMarkerIdx = self.index(self.startIndex, offsetBy: 3, limitedBy: self.endIndex),
            self[self.startIndex] == Unicode.Scalar.asciiLowercasedX,
            self[self.index(self.startIndex, offsetBy: 1)] == Unicode.Scalar.asciiLowercasedN,
            self[self.index(self.startIndex, offsetBy: 2)] == Unicode.Scalar.asciiHyphenMinus,
            self[lastMarkerIdx] == Unicode.Scalar.asciiHyphenMinus
        {
            return true
        } else {
            return false
        }
    }
}
