public import CSwiftIDNA

/// A Unicode scalar value that is known to be valid, which is to say not a surrogate and not above
/// `0x10FFFF`.
@frozen
@usableFromInline
package struct UnicodeScalarValue {
    @usableFromInline
    package let value: UInt32

    /// Makes a scalar out of a value which is not known to be valid, or `nil` if it is not.
    @inlinable
    package init?(_ value: UInt32) {
        guard Self.isValid(value) else { return nil }
        self.value = value
    }

    /// Makes a scalar out of a value that is already known to be valid.
    @inlinable
    package init(_uncheckedAssumingValid value: UInt32) {
        assert(Self.isValid(value))
        self.value = value
    }

    /// Whether the scalar is an ASCII character.
    @inlinable
    package var isASCII: Bool {
        self.value.isASCII
    }

    /// Whether the scalar has `General_Category=Mark`.
    /// [UAX #44, General_Category Values](https://www.unicode.org/reports/tr44/#General_Category_Values)
    @inlinable
    package var isMark: Bool {
        cswift_idna_is_mark(self.value)
    }

    /// Whether the scalar is a valid Unicode scalar value, which is to say not a surrogate and
    /// not above `0x10FFFF`.
    @inlinable
    static func isValid(_ value: UInt32) -> Bool {
        let isSurrogate = (value &- 0xD800) &>> 11 == 0
        let isAboveMaxScalarValue = value > 0x10_FFFF
        return !(isSurrogate || isAboveMaxScalarValue)
    }
}
