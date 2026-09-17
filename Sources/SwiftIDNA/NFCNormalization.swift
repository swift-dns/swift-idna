public import CSwiftIDNA

/// NFC normalization per UAX #15, backed by the trie built by utils/NFCTableGenerator.swift.
@available(SwiftStdlib 5.1, *)
@usableFromInline
package struct NFCNormalization {
    /// Whether the span is in Normalization Form C or not.
    @inlinable
    package static func isInNFC(_ span: Span<UInt8>) -> Bool {
        if Self.isInNFCQuickCheck(span) {
            return true
        }
        return Self._isInNFCSlow(span)
    }

    /// Whether the span is definitely in Normalization Form C.
    ///
    /// `true` means the bytes are in in NFC.
    /// `false` means the bytes might or might not be in NFC.
    ///
    /// https://www.unicode.org/reports/tr15/#Detecting_Normalization_Forms
    @inlinable
    package static func isInNFCQuickCheck(_ span: Span<UInt8>) -> Bool {
        var maxByte: UInt8 = 0
        /// This loop is auto-vectorized by LLVM.
        for idx in span.indices {
            maxByte = max(maxByte, span[idx])
        }
        /// Bytes below 0xCC are always in NFC.
        if maxByte < 0xCC {
            return true
        }

        /// Try scalar by scalar:
        var iterator = UnicodeScalarIterator()
        var lastCanonicalClass: UInt16 = 0
        while let scalar = iterator.next(in: span) {
            if scalar < 0x300 {
                lastCanonicalClass = 0
                continue
            }
            let info = NFCScalarInfo.for(scalar: scalar)
            switch info.tag {
            case .maybe, .maybeWithDecomposition, .decompositionQCNo:
                return false
            case .cccOnly:
                if lastCanonicalClass > info.payload {
                    return false
                }
                lastCanonicalClass = info.payload
            case .inert, .decompositionQCYes, .hangulSyllable:
                lastCanonicalClass = 0
            }
        }
        return true
    }

    /// Whether the span is in Normalization Form C or not.
    @usableFromInline
    @inline(never)
    package static func _isInNFCSlow(_ span: Span<UInt8>) -> Bool {
        unsafe withNormalizedScalars(span) { scalarsCount, scalarsBuffer in
            let scalarsRange = unsafe Range<Int>(uncheckedBounds: (0, scalarsCount))
            let initializedScalars = UnsafeBufferPointer(scalarsBuffer)
            let scalarsSpan = unsafe initializedScalars.span.extracting(unchecked: scalarsRange)

            var utf8Count = 0
            var iterator = UTF8BytesIterator()
            var isEqualToCurrent = 1
            while let (scalarUTF8Length, bytes) = iterator.branchlessNext(in: scalarsSpan) {
                withUnsafeBytes(of: bytes) { bytesPtr in
                    for idx in 0..<scalarUTF8Length {
                        let uncheckedSpanIdx = utf8Count &+ idx
                        let spanIdx = min(uncheckedSpanIdx, span.count &- 1)
                        let spanByte = unsafe span[unchecked: spanIdx]
                        isEqualToCurrent &= unsafe (spanByte == bytesPtr[idx]) ? 1 : 0
                    }
                }
                utf8Count &+= scalarUTF8Length
            }

            return isEqualToCurrent == 1 && utf8Count == span.count
        }
    }

    /// Normalizes the span to Normalization Form C and runs `body` with the result, backed by
    /// temporary stack allocations. Never allocates a Swift heap object.
    @inline(always)
    package static func writeUTF8BytesInNFC<R: ~Copyable>(
        _ span: Span<UInt8>,
        via writingUTF8Bytes: (_ requiredCapacity: Int, ((inout OutputSpan<UInt8>) -> Void)) -> R
    ) -> R {
        unsafe withNormalizedScalars(span) { scalarsCount, scalarsBuffer in
            /// Write utf8 bytes
            writingUTF8Bytes((3 &* span.count) &+ 3) { buffer in
                let scalarsRange = unsafe Range<Int>(uncheckedBounds: (0, scalarsCount))
                let initializedScalars = UnsafeBufferPointer(scalarsBuffer)
                let scalarsSpan = unsafe initializedScalars.span.extracting(unchecked: scalarsRange)

                unsafe buffer.withUnsafeMutableBufferPointer {
                    utf8Buffer,
                    initializedCount in
                    var utf8Count = 0
                    var iterator = UTF8BytesIterator()
                    while let (scalarUTF8Length, bytes) = iterator.branchlessNext(in: scalarsSpan) {
                        unsafe utf8Buffer[utf8Count] = bytes.0
                        unsafe utf8Buffer[utf8Count &+ 1] = bytes.1
                        unsafe utf8Buffer[utf8Count &+ 2] = bytes.2
                        unsafe utf8Buffer[utf8Count &+ 3] = bytes.3
                        utf8Count &+= scalarUTF8Length
                    }
                    initializedCount = utf8Count
                }
            }
        }
    }

    /// Normalizes the span into `scalars` and returns how many scalars it wrote.
    ///
    /// Unlike `withNormalizedScalars(_:block:)` this does not keep `span` borrowed past the
    /// call, so the caller may write the result back over the span's own storage.
    ///
    /// `scalars` must have room for `2 * span.count` elements.
    @inline(always)
    package static func normalizeScalars(
        _ span: Span<UInt8>,
        into scalars: UnsafeMutableBufferPointer<UInt32>
    ) -> Int {
        var scalarsCount = 0
        /// For Normalization Form C, we need to first go through the decomposition step:
        unsafe Self.decompose(span, into: scalars, advancingCount: &scalarsCount)
        /// Then we (re)compose:
        unsafe Self.compose(scalars, advancingCount: &scalarsCount)
        return scalarsCount
    }

    @inline(always)
    package static func withNormalizedScalars<R: ~Copyable>(
        _ span: Span<UInt8>,
        block: (_ scalarsCount: Int, _ scalars: UnsafeMutableBufferPointer<UInt32>) -> R
    ) -> R {
        /// The NFD expansion of any input is at most 2 scalars per input UTF-8 byte, and its
        /// NFC form at most 3 UTF-8 bytes per input UTF-8 byte. The generator verifies both
        /// bounds on every table regeneration.
        withUnsafeTemporaryAllocation(
            of: UInt32.self,
            capacity: 2 &* span.count
        ) { scalarsBuffer in
            var scalarsCount = 0
            /// For Normalization Form C, we need to first go through the decomposition step:
            unsafe Self.decompose(span, into: scalarsBuffer, advancingCount: &scalarsCount)
            /// Then we (re)compose:
            unsafe Self.compose(scalarsBuffer, advancingCount: &scalarsCount)
            return unsafe block(scalarsCount, scalarsBuffer)
        }
    }

    /// Decomposes the span into its canonical decomposed form (NFD).
    /// [The Unicode Standard, 3.7 Decomposition](https://www.unicode.org/versions/Unicode17.0.0/UnicodeStandard-17.0.pdf)
    @inlinable
    static func decompose(
        _ span: Span<UInt8>,
        into scalars: UnsafeMutableBufferPointer<UInt32>,
        advancingCount count: inout Int
    ) {
        var iterator = UnicodeScalarIterator()
        while let scalar = iterator.next(in: span) {
            /// Scalars below U+00C0 are always in NF(K)D & NF(K)C already.
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
                let packedScalar = (UInt32(info.payload) &<< 21) | scalar
                unsafe Self.reorderCanonically(
                    packedScalar: packedScalar,
                    into: scalars,
                    advancingCount: &count
                )
            case .maybeWithDecomposition, .decompositionQCYes, .decompositionQCNo:
                let slice = cswift_idna_nfc_decomposition_slice(UInt32(info.payload))
                let elementOffset = slice &>> 8
                let elementCount = slice & 0xFF

                for elementIndex in 0..<elementCount {
                    let decomposedScalar = cswift_idna_nfc_decomposition_scalar_at(
                        elementOffset &+ elementIndex
                    )
                    unsafe Self.reorderCanonically(
                        packedScalar: decomposedScalar,
                        into: scalars,
                        advancingCount: &count
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

    /// Reorders based on the values of the Canonical Combining Class (CCC).
    /// [The Unicode Standard, 3.11.5 Canonical Ordering Algorithm](https://www.unicode.org/versions/Unicode17.0.0/UnicodeStandard-17.0.pdf)
    @inlinable
    static func reorderCanonically(
        packedScalar: UInt32,
        into scalars: UnsafeMutableBufferPointer<UInt32>,
        advancingCount count: inout Int
    ) {
        /// Canonical Combining Class
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

    /// (Re)composes the span into its canonical composed form (NFC).
    /// [The Unicode Standard, 3.11.6 Canonical Composition Algorithm](https://www.unicode.org/versions/Unicode17.0.0/UnicodeStandard-17.0.pdf)
    @inlinable
    static func compose(
        _ scalars: UnsafeMutableBufferPointer<UInt32>,
        advancingCount count: inout Int
    ) {
        var readIndex = 0
        var writeIndex = 0
        var starterIndex = -1
        /// Canonical Combining Class
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

    /// [The Unicode Standard, 3.11.6 Canonical Composition Algorithm](https://www.unicode.org/versions/Unicode17.0.0/UnicodeStandard-17.0.pdf)
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
}
