extension BinaryInteger {
    /// Turns the byte into a lowercased ASCII letter only if it's an uppercased ASCII letter.
    @inlinable
    public func toLowercasedASCIILetter() -> Self {
        if self.isUppercasedASCIILetter {
            /// https://ss64.com/ascii.html
            /// The difference between an upper and lower cased ASCII byte is their sixth bit.
            /// Turn the sixth bit on to ensure lowercased ASCII byte.
            return self | 0b0010_0000
        } else {
            return self
        }
    }

    /// Turns the character into a lowercased ASCII letter only if it's an uppercased ASCII letter.
    /// Does not check if the value is an uppercased ASCII letter.
    @inlinable
    public func _uncheckedToLowercasedASCIILetterAssumingUppercasedLetter() -> Self {
        /// https://ss64.com/ascii.html
        /// The difference between an upper and lower cased ASCII byte is their sixth bit.
        /// Turn the sixth bit on to ensure lowercased ASCII byte.
        self | 0b0010_0000
    }

    @inlinable
    public var isUppercasedASCIILetter: Bool {
        self >= 0x41 && self <= 0x5A
    }

    /// Returns if the character is an IDNA label separator, like `.` in `mahdibm.com`.
    /// U+002E ( . ) FULL STOP
    /// U+FF0E ( ． ) FULLWIDTH FULL STOP
    /// U+3002 ( 。 ) IDEOGRAPHIC FULL STOP
    /// U+FF61 ( ｡ ) HALFWIDTH IDEOGRAPHIC FULL STOP
    /// https://www.unicode.org/reports/tr46/#Notation
    @inlinable
    public var isIDNALabelSeparator: Bool {
        self == 0x2E
            || self == 0xFF0E
            || self == 0x3002
            || self == 0xFF61
    }

    @inlinable
    static var asciiDot: Self {
        0x2E
    }

    @inlinable
    static var asciiLowercasedX: Self {
        0x78
    }

    @inlinable
    static var asciiLowercasedN: Self {
        0x6E
    }

    @inlinable
    static var asciiHyphenMinus: Self {
        0x2D
    }
}

extension BinaryInteger {
    /// This assumes a non-negative value.
    @inlinable
    var isASCII: Bool {
        self <= 0x7F
    }

    @inlinable
    var isLowercasedLetterOrDigitOrHyphenMinus: Bool {
        self == .asciiHyphenMinus
            || (self <= 0x39 && self >= 0x30)
            || (self >= 0x61 && self <= 0x7A)
    }
}
