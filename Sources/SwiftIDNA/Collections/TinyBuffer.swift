public import BasicContainers

@inlinable
package var TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD: Int {
    36
}

/// A collection of bytes.
/// Holds up to the first 24 elements in a inline stack allocation, and then allocates a
/// `UniqueArray` for the rest if needed.
/// This is useful for skipping allocations if we don't have many bytes to store.
@available(SwiftStdlib 5.1, *)
@usableFromInline
enum TinyBuffer: ~Copyable, ~Escapable {
    case inline(InlineElements)
    case heap(UniqueArray<UInt8>)

    /// Runs `body` with an empty `TinyBuffer` backed by a inline stack allocation.
    @inlinable
    @inline(__always)
    static func withInlineAllocation<R: ~Copyable, Failure: Error>(
        _ body: (inout TinyBuffer) throws(Failure) -> R
    ) throws(Failure) -> R {
        try Self.withInlineAllocation(requiredCapacity: 0, body)
    }

    /// Runs `body` with an empty `TinyBuffer`, unconditionally allocating on the heap if the
    /// requested capacity does not fit inline.
    @inlinable
    @inline(__always)
    static func withInlineAllocation<R: ~Copyable, Failure: Error>(
        requiredCapacity: Int,
        _ body: (inout TinyBuffer) throws(Failure) -> R
    ) throws(Failure) -> R {
        if requiredCapacity > InlineElements.maximumCapacity {
            var buffer = TinyBuffer.heap(UniqueArray<UInt8>(minimumCapacity: requiredCapacity))
            return try body(&buffer)
        }
        return try InlineElements.withInlineAllocation { elements throws(Failure) -> R in
            var buffer = TinyBuffer.inline(elements)
            return try body(&buffer)
        }
    }

    /// Runs `body` with an empty `TinyBuffer`, allocating on the heap if the function sees fit.
    @inlinable
    static func withInlineAllocation<R: ~Copyable, Failure: Error>(
        preferredCapacity: Int,
        _ body: (inout TinyBuffer) throws(Failure) -> R
    ) throws(Failure) -> R {
        /// We have a test to ensure the UniqueArray, after having 24 elements and when you want to
        /// append the 25th element, it will allocate a new buffer with a capacity of 36.
        ///
        /// If the preferred capacity is less than 24, we can use the inline elements anyway to begin
        /// with, because even if we need to allocate a new buffer, we're only allocating once anyway.
        if preferredCapacity > TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD {
            var buffer = TinyBuffer.heap(UniqueArray<UInt8>(minimumCapacity: preferredCapacity))
            return try body(&buffer)
        }
        return try InlineElements.withInlineAllocation { elements throws(Failure) -> R in
            var buffer = TinyBuffer.inline(elements)
            return try body(&buffer)
        }
    }

    /// Count of the bytes in this buffer.
    @inlinable
    var count: Int {
        switch self {
        case .inline(let elements):
            return elements.count
        case .heap(let array):
            return array.count
        }
    }

    /// Whether this buffer is empty.
    @inlinable
    var isEmpty: Bool {
        switch self {
        case .inline(let elements):
            return elements.isEmpty
        case .heap(let array):
            return array.isEmpty
        }
    }

    /// Reserves the requested capacity upfront, if the the function sees fit.
    @inlinable
    mutating func preferablyReserveCapacity(_ preferredCapacity: Int) {
        switch consume self {
        case .inline(let elements):
            /// We have a test to ensure the UniqueArray, after having 23 elements and when you want to
            /// append the 24th element, it will allocate a new buffer with a capacity of 24.
            ///
            /// If the preferred capacity is less than 23, we can use the inline elements anyway to begin
            /// with, because even if we need to allocate a new buffer, we're only allocating once anyway.
            if preferredCapacity > TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD {
                let array = UniqueArray(copying: elements, capacity: preferredCapacity)
                self = .heap(array)
            } else {
                self = .inline(elements)
            }
        case .heap(var array):
            array.reserveCapacity(preferredCapacity)
            self = .heap(array)
        }
    }

    /// Reserves `preferredCapacity` of real capacity, moving to the heap if it will not fit
    @inlinable
    mutating func reserveCapacity(_ preferredCapacity: Int) {
        switch consume self {
        case .inline(let elements):
            if preferredCapacity > InlineElements.maximumCapacity {
                let array = UniqueArray(copying: elements, capacity: preferredCapacity)
                self = .heap(array)
            } else {
                self = .inline(elements)
            }
        case .heap(var array):
            array.reserveCapacity(preferredCapacity)
            self = .heap(array)
        }
    }

    /// Appends the given element to the buffer.
    /// Assumes the buffer has enough capacity to hold the element.
    @inlinable
    mutating func append(unchecked element: UInt8) {
        switch consume self {
        case .inline(var elements):
            elements.append(unchecked: element)
            self = .inline(elements)
        case .heap(var array):
            array.append(element)
            self = .heap(array)
        }
    }

    /// Appends the given span to the buffer.
    @inlinable
    mutating func append(copying span: Span<UInt8>) {
        switch consume self {
        case .inline(var elements):
            let requiredCapacity = span.count + elements.count
            if requiredCapacity > InlineElements.maximumCapacity {
                /// We need to grow the buffer to something more than the amount of bytes we can hold inline.
                var array = UniqueArray(copying: elements, capacity: requiredCapacity)
                array.append(copying: span)
                self = .heap(array)
            } else {
                /// We can hold the bytes inline, so we can just append them directly.
                elements.edit { output in
                    output.swift_idna_append(copying: span)
                }
                self = .inline(elements)
            }
        case .heap(var array):
            array.append(copying: span)
            self = .heap(array)
        }
    }

    /// Removes all the bytes from the buffer.
    @inlinable
    mutating func removeAll(keepingCapacity: Bool) {
        switch consume self {
        case .inline(var elements):
            elements.removeAll()
            self = .inline(elements)
        case .heap(var array):
            array.removeAll(keepingCapacity: keepingCapacity)
            self = .heap(array)
        }
    }

    /// Gives access to the underlying buffer as an `OutputSpan<UInt8>`.
    @inlinable
    mutating func edit(_ block: (inout OutputSpan<UInt8>) -> Void) {
        switch consume self {
        case .inline(var elements):
            elements.edit { output in
                block(&output)
            }
            self = .inline(elements)
        case .heap(var array):
            array.edit { output in
                block(&output)
            }
            self = .heap(array)
        }
    }

    /// Gives access to the underlying buffer as a `Span<UInt8>`.
    @inlinable
    func withSpan<T: ~Copyable>(_ block: (Span<UInt8>) -> T) -> T {
        switch self {
        case .inline(let elements):
            return elements.withSpan(block)
        case .heap(let array):
            return block(array.span)
        }
    }

    /// Reserves the given extra capacity to the buffer, and then
    /// gives access to the underlying buffer as an `OutputSpan<UInt8>`.
    @inlinable
    mutating func append(
        extraRequiredCapacity extraCapacity: Int,
        _ block: (inout OutputSpan<UInt8>) -> Void
    ) {
        /// Use heap if the required capacity requires so
        switch consume self {
        case .inline(var elements):
            let newCapacity = elements.count &+ extraCapacity
            if newCapacity > InlineElements.maximumCapacity {
                /// We need to grow the buffer to something more than the amount of bytes we can hold inline.
                var array = UniqueArray(copying: elements, capacity: newCapacity)
                array.edit { output in
                    block(&output)
                }
                self = .heap(array)
            } else {
                elements.edit { output in
                    block(&output)
                }
                self = .inline(elements)
            }
        case .heap(var array):
            array.append(addingCount: extraCapacity) { output in
                block(&output)
            }
            self = .heap(array)
        }
    }

    /// Appends the given UTF-8 view to the buffer.
    @inlinable
    mutating func append(copying utf8View: Unicode.Scalar.UTF8View) {
        self.append(extraRequiredCapacity: utf8View.count) { output in
            for byte in utf8View {
                output.append(byte)
            }
        }
    }

    /// Inserts the given UTF-8 view at the given index into the buffer.
    @inlinable
    mutating func insert(copying utf8View: Unicode.Scalar.UTF8View, at index: Int) {
        /// Use heap if the required capacity requires so
        switch consume self {
        case .inline(var elements):
            let newCapacity = elements.count &+ utf8View.count
            if newCapacity > InlineElements.maximumCapacity {
                /// We need to grow the buffer to something more than the amount of bytes we can hold inline.
                var array = UniqueArray(copying: elements, capacity: newCapacity)
                array.insert(copying: utf8View, at: index)
                self = .heap(array)
            } else {
                elements.uncheckedInsert(copying: utf8View, at: index)
                self = .inline(elements)
            }
        case .heap(var array):
            array.insert(copying: utf8View, at: index)
            self = .heap(array)
        }
    }

    /// Ensures the buffer contains only valid UTF-8 and NFC-normalized bytes.
    ///
    /// The NFC form of the bytes can be up to 3x as long as the original bytes, so the result
    /// is allowed to move an inline buffer to the heap.
    @inlinable
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        let isAlreadyNFC = self.withSpan { NFCNormalization.quickCheck($0) }
        if isAlreadyNFC {
            return
        }

        switch consume self {
        case .inline(var elements):
            let array = elements.withSpan { span in
                NFCNormalization.withNFCNormalized(span) { normalizedSpan in
                    var array = UniqueArray<UInt8>(minimumCapacity: normalizedSpan.count)
                    array.append(copying: normalizedSpan)
                    return array
                }
            }
            if array.count <= InlineElements.maximumCapacity {
                elements.removeAll()
                elements.edit { output in
                    output.swift_idna_append(copying: array.span)
                }
                self = .inline(elements)
            } else {
                self = .heap(array)
            }
        case .heap(let array):
            let newArray = NFCNormalization.withNFCNormalized(array.span) { normalizedSpan in
                var newArray = UniqueArray<UInt8>(minimumCapacity: normalizedSpan.count)
                newArray.append(copying: normalizedSpan)
                return newArray
            }
            self = .heap(newArray)
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension TinyBuffer {
    /// Some bytes held in a inline stack allocation, alongside their count.
    /// Currently holds up to 24 bytes.
    @usableFromInline
    @safe struct InlineElements: ~Copyable, ~Escapable {
        @usableFromInline
        var buffer: UnsafeMutableBufferPointer<UInt8>
        @usableFromInline
        var count: Int

        /// The maximum number of bytes that can be held inline.
        @inlinable
        static var maximumCapacity: Int {
            24
        }

        @inlinable
        @_lifetime(borrow buffer)
        init(buffer: UnsafeMutableBufferPointer<UInt8>, count: Int) {
            unsafe self.buffer = buffer
            self.count = count
        }

        /// Runs `body` with an empty `InlineElements` backed by a temporary stack allocation.
        ///
        /// This is the only place the backing allocation is made, because this is the type
        /// that actually holds onto it.
        @inlinable
        @inline(__always)
        static func withInlineAllocation<R: ~Copyable, Failure: Error>(
            _ body: (consuming InlineElements) throws(Failure) -> R
        ) throws(Failure) -> R {
            try withUnsafeTemporaryAllocation(
                of: UInt8.self,
                capacity: Self.maximumCapacity
            ) { alloc throws(Failure) -> R in
                try body(unsafe InlineElements(buffer: alloc, count: 0))
            }
        }

        /// Whether this buffer is empty.
        @inlinable
        var isEmpty: Bool {
            self.count == 0
        }

        /// Gives access to the underlying buffer as a `Span<UInt8>`.
        @_transparent
        @inlinable
        func withSpan<T: ~Copyable>(_ body: (Span<UInt8>) throws -> T) rethrows -> T {
            let range = unsafe Range<Int>(uncheckedBounds: (0, self.count))
            let initialized = unsafe UnsafeBufferPointer(self.buffer)
            let span = unsafe initialized.span.extracting(unchecked: range)
            return try body(span)
        }

        /// Appends the given element to the buffer.
        /// Assumes the buffer has enough capacity to hold the element.
        @inlinable
        mutating func append(unchecked element: UInt8) {
            unsafe self.buffer.initializeElement(at: self.count, to: element)
            self.count &+= 1
        }

        /// Removes all the elements from the buffer.
        @inlinable
        mutating func removeAll() {
            self.count = 0
        }

        /// Gives access to the underlying buffer as an `OutputSpan<UInt8>`.
        @inlinable
        mutating func edit(_ block: (inout OutputSpan<UInt8>) -> Void) {
            var span = unsafe OutputSpan(buffer: self.buffer, initializedCount: self.count)

            block(&span)

            let newCount = unsafe span.finalize(for: self.buffer)
            span = OutputSpan()
            self.count = newCount
        }

        /// Inserts the given UTF-8 view at the given index into the buffer.
        ///
        /// This function does not check if these inline elements add up to more than this buffer can hold.
        /// Hence why it is called `"unchecked"Insert`.
        @inlinable
        mutating func uncheckedInsert(copying utf8View: Unicode.Scalar.UTF8View, at index: Int) {
            let usedCapacity = self.count
            let utf8ViewCount = utf8View.count
            let newCount = usedCapacity + utf8ViewCount

            assert(utf8ViewCount != 0)
            assert(newCount <= InlineElements.maximumCapacity)

            let targetRange = unsafe Range<Int>(uncheckedBounds: (index, index &+ utf8ViewCount))
            let target = unsafe self.buffer.extracting(targetRange)

            if targetRange.lowerBound <= usedCapacity {
                let moveRange = unsafe Range<Int>(uncheckedBounds: (index, usedCapacity))
                let moveBytes = unsafe self.buffer.extracting(moveRange)

                let afterRange = unsafe Range<Int>(
                    uncheckedBounds: (
                        targetRange.upperBound,
                        targetRange.upperBound &+ moveBytes.count
                    )
                )
                let afterBytes = unsafe self.buffer.extracting(afterRange)

                _ = unsafe afterBytes.moveInitialize(fromContentsOf: moveBytes)
            }

            _ = unsafe target.initialize(fromContentsOf: utf8View)

            self.count = newCount
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension String {
    /// Initializes a `String` by copying the given inline elements.
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements) {
        self = elements.withSpan { String(_uncheckedAssumingValidUTF8: $0) }
    }
}

@available(SwiftStdlib 5.1, *)
extension UniqueArray<UInt8> {
    /// Initializes a `UniqueArray<UInt8>` by copying the given inline elements.
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements, capacity: Int) {
        assert(capacity > TinyBuffer.InlineElements.maximumCapacity)

        self.init(capacity: capacity) { output in
            elements.withSpan { span in
                output.swift_idna_append(copying: span)
            }
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension [UInt8] {
    /// Initializes a `[UInt8]` by copying the given inline elements.
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements) {
        self = elements.withSpan { [UInt8](copying: $0) }
    }

    /// Initializes a `[UInt8]` by copying the given `TinyBuffer`.
    @inlinable
    init(copying array: borrowing TinyBuffer) {
        switch array {
        case .inline(let elements):
            self = [UInt8](copying: elements)
        case .heap(let array):
            self = [UInt8](copying: array.span)
        }
    }
}

@available(SwiftStdlib 5.1, *)
extension TinyBuffer {
    /// Moves the contents of this buffer out as an `IDNA.ConversionResult`, leaving the buffer empty.
    ///
    /// This exists so the result can be produced from a buffer held by an `inout` binding (such as
    /// a `withTemporary` closure parameter), which cannot be consumed directly.
    @inlinable
    mutating func takeAsConversionResult() -> IDNA.ConversionResult {
        switch consume self {
        case .inline(let elements):
            /// We can just convert the inline elements to a string directly.
            ///
            /// TODO: Just give access to the inline elements instead of converting to a string?
            /// This is not too bad anyway, because if the inline elements hold 15 or less bytes,
            /// `String` will just hold the bytes inline as well.
            /// If there are 16 or more bytes though, an allocation will occur.
            self = .heap(UniqueArray<UInt8>())
            return .string(String(copying: elements))
        case .heap(let array):
            self = .heap(UniqueArray<UInt8>())
            return .bytes(array)
        }
    }
}
