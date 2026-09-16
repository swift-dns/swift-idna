/// An iterator that encodes Unicode scalars into UTF-8 bytes.
@available(SwiftStdlib 5.1, *)
@usableFromInline
struct UTF8BytesIterator {
    @usableFromInline
    var currentScalarOffset: Int

    @inlinable
    init() {
        self.currentScalarOffset = 0
    }

    /// Encodes the next Unicode scalar and returns its UTF-8 bytes alongside how many of them
    /// are significant. The remaining bytes of the tuple are zero.
    /// Always tries to encode regardless if the scalar offset is valid.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func uncheckedNext(
        in scalars: Span<UInt32>
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8)) {
        let packedScalar = unsafe scalars[unchecked: self.currentScalarOffset]
        self.currentScalarOffset &+= 1
        return Self.encodeScalar(packedScalar & 0x1F_FFFF)
    }

    /// [simdutf's scalar utf32-to-utf8 conversion](https://github.com/simdutf/simdutf/blob/master/include/simdutf/scalar/utf32_to_utf8/valid_utf32_to_utf8.h)
    @inline(__always)
    @inlinable
    static func encodeScalar(
        _ scalar: UInt32
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8)) {
        if scalar & 0xFFFF_FF80 == 0 {
            return (
                1,
                (
                    UInt8(truncatingIfNeeded: scalar),
                    0,
                    0,
                    0
                )
            )
        } else if scalar & 0xFFFF_F800 == 0 {
            return (
                2,
                (
                    UInt8(truncatingIfNeeded: 0xC0 | (scalar &>> 6)),
                    UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F)),
                    0,
                    0
                )
            )
        } else if scalar & 0xFFFF_0000 == 0 {
            return (
                3,
                (
                    UInt8(truncatingIfNeeded: 0xE0 | (scalar &>> 12)),
                    UInt8(truncatingIfNeeded: 0x80 | ((scalar &>> 6) & 0x3F)),
                    UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F)),
                    0
                )
            )
        } else {
            return (
                4,
                (
                    UInt8(truncatingIfNeeded: 0xF0 | (scalar &>> 18)),
                    UInt8(truncatingIfNeeded: 0x80 | ((scalar &>> 12) & 0x3F)),
                    UInt8(truncatingIfNeeded: 0x80 | ((scalar &>> 6) & 0x3F)),
                    UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F))
                )
            )
        }
    }

    @inline(__always)
    @inlinable
    mutating func uncheckedBranchlessNext(
        in scalars: Span<UInt32>
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8)) {
        let packedScalar = unsafe scalars[unchecked: self.currentScalarOffset]
        self.currentScalarOffset &+= 1
        return Self.encode(uncheckedScalar: packedScalar & 0x1F_FFFF)
    }

    /// How many UTF-8 bytes the scalar would encode into.
    @inline(__always)
    @inlinable
    static func utf8Length(uncheckedScalar scalar: UInt32) -> Int {
        /// Valid UTF-32 scalars are in the range `0x0000_0000` to `0x10FFFF`.
        assert(scalar <= 0x1F_FFFF)

        return Int(
            1
                &+ ((0x7F &- scalar) &>> 31)
                &+ ((0x7FF &- scalar) &>> 31)
                &+ ((0xFFFF &- scalar) &>> 31)
        )
    }

    /// The inverse of `UnicodeScalarIterator.decodeScalar`.
    @inline(__always)
    @inlinable
    static func encode(
        uncheckedScalar scalar: UInt32
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8)) {
        let scalarUTF8Length = Self.utf8Length(uncheckedScalar: scalar)
        let shifted = scalar &<< (6 &* (4 &- scalarUTF8Length))
        let leadPrefix = (0xF0E0_C000 as UInt32) &>> (8 &* (scalarUTF8Length &- 1)) & 0xFF
        return (
            scalarUTF8Length,
            (
                UInt8(truncatingIfNeeded: (shifted &>> 18) | leadPrefix),
                UInt8(truncatingIfNeeded: 0x80 | ((shifted &>> 12) & 0x3F)),
                UInt8(truncatingIfNeeded: 0x80 | ((shifted &>> 6) & 0x3F)),
                UInt8(truncatingIfNeeded: 0x80 | (shifted & 0x3F))
            )
        )
    }

    /// Encodes the next Unicode scalar and returns its UTF-8 bytes alongside how many of them
    /// are significant. The remaining bytes of the tuple are `0x80` placeholders.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func branchlessNext(
        in scalars: Span<UInt32>
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8))? {
        guard self.currentScalarOffset < scalars.count else { return nil }
        return self.uncheckedBranchlessNext(in: scalars)
    }

    /// Encodes the next Unicode scalar and returns its UTF-8 bytes alongside how many of them
    /// are significant. The remaining bytes of the tuple are zero.
    ///
    /// Only pass the same span to any single instance of this iterator.
    /// As always, tests will fail if this is not the case.
    @inline(__always)
    @inlinable
    mutating func next(
        in scalars: Span<UInt32>
    ) -> (scalarUTF8Length: Int, bytes: (UInt8, UInt8, UInt8, UInt8))? {
        guard self.currentScalarOffset < scalars.count else { return nil }
        return self.uncheckedNext(in: scalars)
    }
}
