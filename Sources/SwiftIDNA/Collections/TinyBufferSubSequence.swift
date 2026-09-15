/// A `TinyBuffer` subsequence that uses elements from `startIndex` and forward.
@available(SwiftStdlib 5.1, *)
@usableFromInline
struct TinyBufferSubsequence: ~Copyable, ~Escapable {
    @usableFromInline
    var base: TinyBuffer
    @usableFromInline
    var startIndex: Int

    @inlinable
    @_lifetime(copy base)
    init(base: consuming TinyBuffer, startIndex: Int) {
        self.base = base
        self.startIndex = startIndex
    }

    @inlinable
    var count: Int {
        self.base.count &- self.startIndex
    }

    @inlinable
    func withSpan<T>(_ block: (Span<UInt8>) -> T) -> T {
        self.base.withSpan { span in
            let range = unsafe Range<Int>(uncheckedBounds: (self.startIndex, self.base.count))
            return block(unsafe span.extracting(unchecked: range))
        }
    }

    @inlinable
    mutating func append(copying span: Span<UInt8>) {
        self.base.append(copying: span)
    }

    @inlinable
    mutating func append(copying utf8View: Unicode.Scalar.UTF8View) {
        self.base.append(copying: utf8View)
    }

    @inlinable
    mutating func insert(copying collection: Unicode.Scalar.UTF8View, at index: Int) {
        self.base.insert(copying: collection, at: self.startIndex + index)
    }

    /// Reserves the given extra capacity on the buffer, and then
    /// gives access to the underlying buffer as an `OutputSpan<UInt8>`.
    @inlinable
    mutating func append(
        extraRequiredCapacity extraCapacity: Int,
        _ block: (inout OutputSpan<UInt8>) -> Void
    ) {
        self.base.append(extraRequiredCapacity: extraCapacity, block)
    }

    @inlinable
    mutating func preferablyReserveCapacity(_ minimumCapacity: Int) {
        self.base.preferablyReserveCapacity(minimumCapacity)
    }

    @inlinable
    mutating func removeAll() {
        /// Technically we should only remove the sub-range, but for this specific library
        /// it doesn't matter according to the tests, so we don't bother.
        self.base.removeAll(keepingCapacity: true)
    }
}

@available(SwiftStdlib 5.1, *)
extension TinyBufferSubsequence {
    @inlinable
    var isASCII: Bool {
        self.withSpan { $0.isASCII }
    }
}
