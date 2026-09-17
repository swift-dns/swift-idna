public import BasicContainers

/// The number of bytes an IDNA scratch buffer keeps in its stack allocation before spilling
/// over to the heap.
@inlinable
package var TEMPORARY_ARRAY__STACK_SEED_CAPACITY: Int {
    64
}

/// The capacity a full stack seed spills into.
///
/// `TemporaryArray` grows by a factor of 1.5, which is what this mirrors. A preferred capacity
/// at or below this is not worth a heap allocation up front, because the stack seed absorbs it
/// with at most one allocation anyway.
@inlinable
package var TEMPORARY_ARRAY__HEAP_SEED_THRESHOLD: Int {
    (3 &* TEMPORARY_ARRAY__STACK_SEED_CAPACITY &+ 1) / 2
}

/// The number of UTF-8 bytes a `String` holds inline, without allocating.
///
/// Mirrors the standard library's `_SmallString.capacity`:
/// https://github.com/swiftlang/swift/blob/main/stdlib/public/core/SmallString.swift
@inlinable
package var MAX_INLINE_STRING_UTF8_COUNT: Int {
    #if os(watchOS) && _pointerBitWidth(_32)
    10
    #elseif _pointerBitWidth(_32) || _pointerBitWidth(_16)
    8
    #elseif os(Android) && arch(arm64)
    14
    #else
    15
    #endif
}

/// Runs `body` with an empty scratch buffer backed by a stack allocation.
@available(SwiftStdlib 5.1, *)
@inlinable
@inline(__always)
package func withIDNATemporaryBuffer<R: ~Copyable, Failure: Error>(
    _ body: (inout TemporaryArray<UInt8>) throws(Failure) -> R
) throws(Failure) -> R {
    try withTemporaryArray(
        of: UInt8.self,
        capacity: TEMPORARY_ARRAY__STACK_SEED_CAPACITY,
        body
    )
}

/// Runs `body` with an empty scratch buffer, allocating on the heap up front if the function
/// sees fit.
@available(SwiftStdlib 5.1, *)
@inlinable
@inline(__always)
func withIDNATemporaryBuffer<R: ~Copyable, Failure: Error>(
    preferredCapacity: Int,
    _ body: (inout TemporaryArray<UInt8>) throws(Failure) -> R
) throws(Failure) -> R {
    if preferredCapacity > TEMPORARY_ARRAY__HEAP_SEED_THRESHOLD {
        var buffer = TemporaryArray<UInt8>(capacity: preferredCapacity)
        return try body(&buffer)
    }
    return try withTemporaryArray(
        of: UInt8.self,
        capacity: TEMPORARY_ARRAY__STACK_SEED_CAPACITY,
        body
    )
}

@available(SwiftStdlib 5.1, *)
extension TemporaryArray<UInt8> {
    /// Removes all the bytes from the buffer, keeping its current capacity.
    ///
    /// `TemporaryArray.removeAll(keepingCapacity:)` is gated behind a Swift 6.4 compiler and the
    /// `UnstableContainersPreview` trait, so this goes through `edit`, which is gated behind
    /// neither.
    @inlinable
    mutating func removeAllKeepingCapacity() {
        self.edit { output in
            output.removeAll()
        }
    }

    /// Appends the given UTF-8 view to the buffer.
    @inlinable
    mutating func append(copying utf8View: Unicode.Scalar.UTF8View) {
        self.append(addingCount: utf8View.count) { output in
            for byte in utf8View {
                output.append(byte)
            }
        }
    }

    /// Ensures the buffer contains only valid UTF-8 and NFC-normalized bytes.
    ///
    /// The NFC form of the bytes can be up to 3x as long as the original bytes, so the result
    /// is allowed to spill an otherwise stack-backed buffer over to the heap.
    @inlinable
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        if NFCNormalization.isInNFCQuickCheck(self.span) {
            return
        }

        _uncheckedAssumingValidUTF8_renormalizeToNFC(&self)
    }

    /// Whether this buffer is still using the stack allocation it was seeded with.
    ///
    /// The seed capacity is only ever left behind by a reallocation, which both takes ownership
    /// of heap storage and raises the capacity past the seed, so an unchanged capacity means the
    /// bytes are still on the stack. `take()` has to allocate and copy in that case, and is a
    /// free transfer of ownership otherwise.
    @inlinable
    var isStillOnTheStack: Bool {
        self.capacity == TEMPORARY_ARRAY__STACK_SEED_CAPACITY
    }

    /// Moves the contents of this buffer out as an `IDNA.ConversionResult`, leaving the buffer
    /// empty.
    ///
    /// This exists so the result can be produced from a buffer held by an `inout` binding (such
    /// as a `withTemporaryArray` closure parameter), which cannot be consumed directly.
    ///
    /// Bytes that are still on the stack have to be copied out either way, so they go out as a
    /// `String` and spare the consumer a second allocation. Short results go out as a `String`
    /// too, because `String` holds them inline and so costs nothing at all. Anything else is
    /// already in owned heap storage, which `take()` hands over without copying.
    @inlinable
    mutating func takeAsConversionResult() -> IDNA.ConversionResult {
        if self.isStillOnTheStack || self.count <= MAX_INLINE_STRING_UTF8_COUNT {
            let string = String(_uncheckedAssumingValidUTF8: self.span)
            self.removeAllKeepingCapacity()
            return .string(string)
        }
        return .bytes(self.take())
    }
}

/// Rewrites `buffer` with the NFC form of its own bytes.
///
/// The scalars are normalized into a temporary allocation first, which ends the borrow of the
/// buffer and lets the UTF-8 be written straight back over it. Nothing is allocated on the heap
/// unless the NFC form no longer fits in the buffer.
///
/// Only reached when the quick check says the bytes are not already NFC, so this is not worth
/// inlining into the conversion paths at all: doing so measurably hurts their code layout.
@available(SwiftStdlib 5.1, *)
@usableFromInline
@inline(never)
func _uncheckedAssumingValidUTF8_renormalizeToNFC(_ buffer: inout TemporaryArray<UInt8>) {
    /// The NFD expansion of any input is at most 2 scalars per input UTF-8 byte. The generator
    /// verifies that bound on every table regeneration.
    withUnsafeTemporaryAllocation(
        of: UInt32.self,
        capacity: 2 &* buffer.count
    ) { scalars in
        let scalarsCount = unsafe NFCNormalization.normalizeScalars(buffer.span, into: scalars)

        let range = unsafe Range<Int>(uncheckedBounds: (0, scalarsCount))
        let initialized = UnsafeBufferPointer(scalars)
        let scalarsSpan = unsafe initialized.span.extracting(unchecked: range)

        var utf8Count = 0
        for idx in scalarsSpan.indices {
            utf8Count &+= UTF8BytesIterator.utf8Length(
                uncheckedPackedScalar: unsafe scalarsSpan[unchecked: idx]
            )
        }

        buffer.removeAllKeepingCapacity()
        buffer.append(addingCount: utf8Count) { output in
            var iterator = UTF8BytesIterator()
            while let (utf8Length, bytes) = iterator.branchlessNext(in: scalarsSpan) {
                output.swift_idna_append(encodedScalar: bytes, count: utf8Length)
            }
        }
    }
}
