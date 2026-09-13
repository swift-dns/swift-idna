public import CSwiftIDNA

@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct NFCScalarInfo {
    @usableFromInline
    package enum Tag: UInt16 {
        case inert = 0
        case cccOnly = 1
        case maybe = 2
        case maybeWithDecomposition = 3
        case decompositionQCYes = 4
        case decompositionQCNo = 5
        case hangulSyllable = 6
    }

    @usableFromInline
    package let tag: Tag
    /// The scalar's canonical combining class for the `cccOnly` and `maybe` tags, or an index
    /// into the decomposition slices for the decomposing tags. Otherwise always 0.
    @usableFromInline
    package let payload: UInt16

    @inlinable
    init(tag: Tag, payload: UInt16) {
        self.tag = tag
        self.payload = payload
    }

    /// Look up NFC normalization info for a given Unicode scalar.
    /// - Parameter scalar: The Unicode scalar value to look up
    /// - Returns: The corresponding `NFCScalarInfo` value
    @inlinable
    package static func `for`(scalar: UInt32) -> NFCScalarInfo {
        let packedValue = cswift_idna_nfc_value(scalar)
        /// This is exhaustively tested, so `unsafelyUnwrapped` is safe.
        let tag = unsafe Tag(rawValue: packedValue >> 13).unsafelyUnwrapped
        return NFCScalarInfo(tag: tag, payload: packedValue & 0x1FFF)
    }
}

/// NFC normalization per UAX #15, backed by the trie built by utils/NFCTableGenerator.swift.
@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct NFCNormalization {
    /// Whether the span is definitely in Normalization Form C.
    ///
    /// A `false` return does not prove the span is not in NFC; it only means the quick check
    /// could not prove that it is, and the full normalization is required to decide.
    @inlinable
    package static func quickCheck(_ span: Span<UInt8>) -> Bool {
        var maxByte: UInt8 = 0
        /// This loop is auto-vectorized into SIMD instructions by LLVM.
        for idx in span.indices {
            maxByte = max(maxByte, span[idx])
        }
        /// All scalars below U+0300 are NFC_QC=Yes with ccc=0, and every UTF-8 byte of their
        /// encodings is below 0xCC: 2-byte lead bytes reach 0xCB at U+02FF, continuation bytes
        /// stay below 0xC0, and 3/4-byte lead bytes (0xE0+) only encode scalars above U+07FF.
        /// The generator verifies the scalar-side claim on every table regeneration.
        if maxByte < 0xCC {
            return true
        }
        return Self.quickCheckScalarByScalar(span)
    }

    /// The UAX #15 NFC quick check: fails on any NFC_QC=No/Maybe scalar or any canonical
    /// ordering violation.
    @inlinable
    static func quickCheckScalarByScalar(_ span: Span<UInt8>) -> Bool {
        var iterator = UnicodeScalarIterator()
        var previousCCC: UInt16 = 0
        while let scalar = iterator.next(in: span) {
            if scalar < 0x300 {
                previousCCC = 0
                continue
            }
            let info = NFCScalarInfo.for(scalar: scalar)
            switch info.tag {
            case .maybe, .maybeWithDecomposition, .decompositionQCNo:
                return false
            case .cccOnly:
                if previousCCC > info.payload {
                    return false
                }
                previousCCC = info.payload
            case .inert, .decompositionQCYes, .hangulSyllable:
                previousCCC = 0
            }
        }
        return true
    }

    /// Normalizes the span to Normalization Form C and runs `body` with the result, backed by
    /// temporary stack allocations. Never allocates a Swift heap object.
    @inlinable
    package static func withNFCNormalized<R: ~Copyable, Failure: Error>(
        _ span: Span<UInt8>,
        _ body: (Span<UInt8>) throws(Failure) -> R
    ) throws(Failure) -> R {
        /// The NFD expansion of any input is at most 2 scalars per input UTF-8 byte, and its
        /// NFC form at most 3 UTF-8 bytes per input UTF-8 byte. The generator verifies both
        /// bounds on every table regeneration.
        try withUnsafeTemporaryAllocation(
            of: UInt32.self,
            capacity: 2 &* span.count
        ) { scalarsAllocation throws(Failure) -> R in
            var scalarsCount = 0
            unsafe Self.decomposeAndReorder(span, into: scalarsAllocation, count: &scalarsCount)
            unsafe Self.composeInPlace(scalarsAllocation, count: &scalarsCount)
            return try unsafe Self.withUTF8Encoded(
                scalarsAllocation,
                count: scalarsCount,
                maximumUTF8Count: 3 &* span.count,
                body
            )
        }
    }

    /// The canonical decomposition pass: emits the full NFD expansion of every scalar, keeping
    /// the output canonically ordered as it goes.
    @inlinable
    static func decomposeAndReorder(
        _ span: Span<UInt8>,
        into scalars: UnsafeMutableBufferPointer<UInt32>,
        count: inout Int
    ) {
        var iterator = UnicodeScalarIterator()
        while let scalar = iterator.next(in: span) {
            /// Scalars below U+00C0 never carry normalization data.
            /// The generator verifies this claim on every table regeneration.
            if scalar < 0xC0 {
                unsafe scalars[count] = scalar
                count &+= 1
                continue
            }
            let info = NFCScalarInfo.for(scalar: scalar)
            switch info.tag {
            case .inert:
                unsafe scalars[count] = scalar
                count &+= 1
            case .cccOnly, .maybe:
                unsafe Self.reorderedAppend(
                    (UInt32(info.payload) &<< 21) | scalar,
                    into: scalars,
                    count: &count
                )
            case .maybeWithDecomposition, .decompositionQCYes, .decompositionQCNo:
                let slice = cswift_idna_nfc_decomposition_slice(UInt32(info.payload))
                let elementOffset = slice &>> 8
                let elementCount = slice & 0xFF
                for elementIndex in 0..<elementCount {
                    unsafe Self.reorderedAppend(
                        cswift_idna_nfc_decomposition_scalar_at(elementOffset &+ elementIndex),
                        into: scalars,
                        count: &count
                    )
                }
            case .hangulSyllable:
                let syllableIndex = scalar &- 0xAC00
                unsafe scalars[count] = 0x1100 &+ (syllableIndex / 588)
                unsafe scalars[count &+ 1] = 0x1161 &+ ((syllableIndex % 588) / 28)
                count &+= 2
                let trailingIndex = syllableIndex % 28
                if trailingIndex != 0 {
                    unsafe scalars[count] = 0x11A7 &+ trailingIndex
                    count &+= 1
                }
            }
        }
    }

    /// Appends a (ccc, scalar) element, sliding it left past any elements with a higher ccc,
    /// per the Canonical Ordering Algorithm.
    @inlinable
    static func reorderedAppend(
        _ packedScalar: UInt32,
        into scalars: UnsafeMutableBufferPointer<UInt32>,
        count: inout Int
    ) {
        let ccc = packedScalar &>> 21
        var targetIndex = count
        if ccc != 0 {
            while targetIndex > 0, unsafe scalars[targetIndex &- 1] &>> 21 > ccc {
                targetIndex &-= 1
            }
        }
        var moveIndex = count
        while moveIndex > targetIndex {
            unsafe scalars[moveIndex] = unsafe scalars[moveIndex &- 1]
            moveIndex &-= 1
        }
        unsafe scalars[targetIndex] = packedScalar
        count &+= 1
    }

    /// The Canonical Composition Algorithm per UAX #15: composes each combinable scalar with
    /// the last starter unless a preceding scalar blocks it, compacting survivors in place.
    @inlinable
    static func composeInPlace(
        _ scalars: UnsafeMutableBufferPointer<UInt32>,
        count: inout Int
    ) {
        var readIndex = 0
        var writeIndex = 0
        var starterIndex = -1
        var previousCCC: UInt32 = 0
        while readIndex < count {
            let packedScalar = unsafe scalars[readIndex]
            readIndex &+= 1
            let ccc = packedScalar &>> 21
            let scalar = packedScalar & 0x1F_FFFF

            if starterIndex >= 0,
                previousCCC < ccc || previousCCC == 0
            {
                let starter = unsafe scalars[starterIndex] & 0x1F_FFFF
                if let composite = Self.composePair(starter, scalar) {
                    unsafe scalars[starterIndex] = composite
                    continue
                }
            }

            unsafe scalars[writeIndex] = packedScalar
            starterIndex = ccc == 0 ? writeIndex : starterIndex
            previousCCC = ccc
            writeIndex &+= 1
        }
        count = writeIndex
    }

    /// Returns the primary composite of the two scalars, composing Hangul arithmetically and
    /// everything else through a binary search of the canonical composition pair table.
    @inlinable
    package static func composePair(_ first: UInt32, _ second: UInt32) -> UInt32? {
        if first &- 0x1100 < 19, second &- 0x1161 < 21 {
            let leadingIndex = first &- 0x1100
            let vowelIndex = second &- 0x1161
            return 0xAC00 &+ ((leadingIndex &* 21 &+ vowelIndex) &* 28)
        }
        if first &- 0xAC00 < 11172, (first &- 0xAC00) % 28 == 0, second &- 0x11A8 < 27 {
            return first &+ (second &- 0x11A7)
        }

        let key = (UInt64(first) &<< 43) | (UInt64(second) &<< 22)
        var low: Int32 = 0
        var high: Int32 = cswift_idna_nfc_composition_pairs_count
        while low < high {
            let mid = (low &+ high) / 2
            let candidate = cswift_idna_nfc_composition_pair(mid)
            if candidate &>> 22 == key &>> 22 {
                return UInt32(truncatingIfNeeded: candidate) & 0x3F_FFFF
            } else if candidate < key {
                low = mid &+ 1
            } else {
                high = mid
            }
        }
        return nil
    }

    /// Encodes the composed scalars back into UTF-8 in a temporary stack allocation and runs
    /// `body` with the result.
    @inlinable
    static func withUTF8Encoded<R: ~Copyable, Failure: Error>(
        _ scalars: UnsafeMutableBufferPointer<UInt32>,
        count: Int,
        maximumUTF8Count: Int,
        _ body: (Span<UInt8>) throws(Failure) -> R
    ) throws(Failure) -> R {
        try withUnsafeTemporaryAllocation(
            of: UInt8.self,
            capacity: maximumUTF8Count
        ) { utf8Allocation throws(Failure) -> R in
            var utf8Count = 0
            var scalarIndex = 0
            while scalarIndex < count {
                let scalar = unsafe scalars[scalarIndex] & 0x1F_FFFF
                scalarIndex &+= 1
                if scalar < 0x80 {
                    unsafe utf8Allocation[utf8Count] = UInt8(truncatingIfNeeded: scalar)
                    utf8Count &+= 1
                } else if scalar < 0x800 {
                    unsafe utf8Allocation[utf8Count] = UInt8(
                        truncatingIfNeeded: 0xC0 | (scalar &>> 6)
                    )
                    unsafe utf8Allocation[utf8Count &+ 1] = UInt8(
                        truncatingIfNeeded: 0x80 | (scalar & 0x3F)
                    )
                    utf8Count &+= 2
                } else if scalar < 0x1_0000 {
                    unsafe utf8Allocation[utf8Count] = UInt8(
                        truncatingIfNeeded: 0xE0 | (scalar &>> 12)
                    )
                    unsafe utf8Allocation[utf8Count &+ 1] = UInt8(
                        truncatingIfNeeded: 0x80 | ((scalar &>> 6) & 0x3F)
                    )
                    unsafe utf8Allocation[utf8Count &+ 2] = UInt8(
                        truncatingIfNeeded: 0x80 | (scalar & 0x3F)
                    )
                    utf8Count &+= 3
                } else {
                    unsafe utf8Allocation[utf8Count] = UInt8(
                        truncatingIfNeeded: 0xF0 | (scalar &>> 18)
                    )
                    unsafe utf8Allocation[utf8Count &+ 1] = UInt8(
                        truncatingIfNeeded: 0x80 | ((scalar &>> 12) & 0x3F)
                    )
                    unsafe utf8Allocation[utf8Count &+ 2] = UInt8(
                        truncatingIfNeeded: 0x80 | ((scalar &>> 6) & 0x3F)
                    )
                    unsafe utf8Allocation[utf8Count &+ 3] = UInt8(
                        truncatingIfNeeded: 0x80 | (scalar & 0x3F)
                    )
                    utf8Count &+= 4
                }
            }

            let range = unsafe Range<Int>(uncheckedBounds: (0, utf8Count))
            let initialized = UnsafeBufferPointer(utf8Allocation)
            let span = unsafe initialized.span.extracting(unchecked: range)
            return try body(span)
        }
    }
}
