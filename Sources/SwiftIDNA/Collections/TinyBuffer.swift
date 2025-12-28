public import BasicContainers

@inlinable
package var TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD: Int {
    35
}

/// A collection of bytes.
/// Holds up to the first 23 elements inline, and then allocates a `UniqueArray` for the rest if needed.
/// This is useful for skipping allocations if we don't have many bytes to store.
@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
enum TinyBuffer: ~Copyable {
    case inline(InlineElements)
    case heap(UniqueArray<UInt8>)

    @inlinable
    init() {
        self = .inline(InlineElements())
    }

    /// Initializes a `TinyBuffer`, unconditionally reserving the requested capacity.
    @inlinable
    init(requiredCapacity: Int) {
        if requiredCapacity > InlineElements.maximumCapacity {
            self = .heap(UniqueArray<UInt8>(capacity: requiredCapacity))
        } else {
            self = .inline(InlineElements())
        }
    }

    /// Initializes a `TinyBuffer`, reserving the requested capacity if the it sees fit.
    @inlinable
    init(preferredCapacity: Int) {
        /// We have a test to ensure the UniqueArray, after having 23 elements and when you want to
        /// append the 24th element, it will allocate a new buffer with a capacity of 24.
        ///
        /// If the preferred capacity is less than 23, we can use the inline elements anyway to begin
        /// with, because even if we need to allocate a new buffer, we're only allocating once anyway.
        if preferredCapacity > TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD {
            self = .heap(UniqueArray<UInt8>(capacity: preferredCapacity))
        } else {
            self = .inline(InlineElements())
        }
    }

    /// Count of the bytes in this buffer.
    @inlinable
    var count: Int {
        switch self {
        case .inline(let elements):
            return Int(elements.count)
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
            let requiredCapacity = span.count + Int(elements.count)
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
    func withSpan<T>(_ block: (Span<UInt8>) -> T) -> T {
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
        exactExtraRequiredCapacity extraCapacity: Int,
        _ block: (inout OutputSpan<UInt8>) -> Void
    ) {
        /// Use heap if the required capacity requires so
        switch consume self {
        case .inline(var elements):
            let newCapacity = Int(elements.count) &+ extraCapacity
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
            array.append(count: extraCapacity) { output in
                block(&output)
            }
            self = .heap(array)
        }
    }

    /// Appends the given UTF-8 view to the buffer.
    @inlinable
    mutating func append(copying utf8View: Unicode.Scalar.UTF8View) {
        self.append(exactExtraRequiredCapacity: utf8View.count) { output in
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
            let newCapacity = Int(elements.count) &+ utf8View.count
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
    @inlinable
    mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
        switch consume self {
        case .inline(var elements):
            elements._uncheckedAssumingValidUTF8_ensureNFC()
            self = .inline(elements)
        case .heap(var array):
            array._uncheckedAssumingValidUTF8_ensureNFC()
            self = .heap(array)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension TinyBuffer {
    /// Some inline bytes, last of which is the count byte.
    /// Currently 23 bytes + 1 count bytes == 24 bytes == 3 x 8 bytes == 3 x UInt64.
    @usableFromInline
    struct InlineElements: ~Copyable {
        @usableFromInline
        typealias BitPattern = (UInt64, UInt64, UInt64)

        @usableFromInline
        var bits: BitPattern

        /// The maximum number of bytes that can be held inline.
        @inlinable
        static var maximumCapacity: Int {
            23
        }

        /// The index of the count byte in the `bits` tuple.
        ///
        /// Meaning that the count of elements in this buffer is the same as the following expression:
        /// ```swift
        /// let countOfElements = withUnsafeBytes(of: bits) { $0[Self.countByteIndex] }
        /// ```
        @inlinable
        static var countByteIndex: Int {
            Self.maximumCapacity
        }

        @inlinable
        init() {
            self.bits = (0, 0, 0)
        }

        /// The count of elements in this buffer.
        @inlinable
        var count: UInt8 {
            withUnsafeBytes(of: bits.2) {
                $0[7]
            }
        }

        /// Whether this buffer is empty.
        @inlinable
        var isEmpty: Bool {
            self.count == 0
        }

        /// Whether this buffer contains only ASCII bytes.
        @inlinable
        var isASCII: Bool {
            self.withSpan { $0.isASCII }
        }

        /// Gives access to the underlying buffer as a `Span<UInt8>`.
        @_transparent
        @inlinable
        func withSpan<T>(_ body: (Span<UInt8>) throws -> T) rethrows -> T {
            try withUnsafeBytes(of: bits) { bitsPtr in
                try bitsPtr.withMemoryRebound(to: UInt8.self) { bitsBytes in
                    let count = bitsPtr[Self.countByteIndex]
                    let bytesSpan = bitsBytes.span.extracting(unchecked: 0..<Int(count))
                    return try body(bytesSpan)
                }
            }
        }

        /// Appends the given element to the buffer.
        /// Assumes the buffer has enough capacity to hold the element.
        @inlinable
        mutating func append(unchecked element: UInt8) {
            withUnsafeMutableBytes(of: &bits) { bitsPtr in
                let count = bitsPtr[Self.countByteIndex]
                bitsPtr[Int(count)] = element
                bitsPtr[Self.countByteIndex] = count &+ 1
            }
        }

        /// Removes all the elements from the buffer.
        @inlinable
        mutating func removeAll() {
            self.bits = (0, 0, 0)
        }

        /// Gives access to the underlying buffer as an `OutputSpan<UInt8>`.
        @inlinable
        mutating func edit(_ block: (inout OutputSpan<UInt8>) -> Void) {
            withUnsafeMutableBytes(of: &self.bits) { bitsPtr in
                bitsPtr.withMemoryRebound(to: UInt8.self) { bytesPtr in
                    let count = Int(bitsPtr[Self.countByteIndex])
                    let mutableBytes = bytesPtr.extracting(0..<Self.maximumCapacity)
                    var span = OutputSpan(buffer: mutableBytes, initializedCount: count)

                    block(&span)

                    let newCount = span.finalize(for: mutableBytes)
                    span = OutputSpan()
                    bitsPtr[Self.countByteIndex] = UInt8(newCount)
                }
            }
        }

        /// Inserts the given UTF-8 view at the given index into the buffer.
        ///
        /// This function does not check if these inline elements add up to more than this buffer can hold.
        /// Hence why it is called `"unchecked"Insert`.
        @inlinable
        mutating func uncheckedInsert(copying utf8View: Unicode.Scalar.UTF8View, at index: Int) {
            withUnsafeMutableBytes(of: &self.bits) { bitsPtr in
                bitsPtr.withMemoryRebound(to: UInt8.self) { bytesPtr in
                    let count = bitsPtr[Self.countByteIndex]
                    let usedCapacity = Int(count)
                    let utf8ViewCount = utf8View.count
                    let newCount = usedCapacity + utf8ViewCount

                    assert(utf8ViewCount != 0)
                    assert(newCount <= InlineElements.maximumCapacity)

                    /// Move the element that is going to be overwritten, to exactly after the
                    /// new elements will be.
                    bitsPtr[newCount] = bitsPtr[index]

                    let targetRange = Range<Int>(uncheckedBounds: (index, index &+ utf8ViewCount))
                    let target = bytesPtr.extracting(targetRange)

                    if targetRange.lowerBound <= usedCapacity {
                        let afterRange = Range(
                            uncheckedBounds: (
                                targetRange.upperBound,
                                Self.countByteIndex
                            )
                        )
                        let afterBytes = bytesPtr.extracting(afterRange)

                        let moveRange = Range<Int>(uncheckedBounds: (index, usedCapacity))
                        let moveBytes = bytesPtr.extracting(moveRange)

                        _ = afterBytes.moveInitialize(fromContentsOf: moveBytes)
                    }

                    _ = target.initialize(fromContentsOf: utf8View)

                    bitsPtr[Self.countByteIndex] = UInt8(newCount)
                }
            }
        }

        /// Ensures the buffer contains only valid UTF-8 and NFC-normalized bytes.
        @inlinable
        mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
            if self.isEmpty || self.isASCII { return }

            let string = String(copying: self)

            self.removeAll()
            self.edit { output in
                string._withNFCCodeUnits { utf8Byte in
                    output.append(utf8Byte)
                }
            }
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension String {
    /// Initializes a `String` by copying the given inline elements.
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements) {
        self = elements.withSpan { String(_uncheckedAssumingValidUTF8: $0) }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension UniqueArray<UInt8> {
    /// Initializes a `UniqueArray<UInt8>` by copying the given inline elements.
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements, capacity: Int) {
        assert(capacity > TinyBuffer.InlineElements.maximumCapacity)

        self.init(capacity: capacity) { output in
            output.withUnsafeMutableBufferPointer { outputPtr, initializedCount in
                withUnsafeBytes(of: elements.bits) { bitsPtr in
                    bitsPtr.withMemoryRebound(to: UInt8.self) { bitsBytes in
                        let count = Int(bitsPtr[TinyBuffer.InlineElements.countByteIndex])
                        let elements = bitsBytes.extracting(0..<count)
                        _ = outputPtr.initialize(fromContentsOf: elements)
                        initializedCount = count
                    }
                }
            }
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
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

@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNA.ConversionResult {
    /// Initializes a `IDNA.ConversionResult` by consuming the given `TinyBuffer`.
    @inlinable
    init(consuming array: consuming TinyBuffer) {
        switch consume array {
        case .inline(let elements):
            /// We can just convert the inline elements to a string directly.
            ///
            /// TODO: Just give access to the inline elements instead of converting to a string?
            /// This is not too bad anyway, because if the inline elements hold 15 or less bytes,
            /// `String` will just hold the bytes inline as well.
            /// If there are 16 or more bytes though, an allocation will occur.
            self = .string(String(copying: elements))
        case .heap(let array):
            self = .bytes(array)
        }
    }
}
