public import BasicContainers

@inlinable
package var TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD: Int {
    35
}

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
enum TinyBuffer: ~Copyable {
    case inline(InlineElements)
    case heap(UniqueArray<UInt8>)

    @inlinable
    init() {
        self = .inline(InlineElements())
    }

    @inlinable
    init(requiredCapacity: Int) {
        if requiredCapacity > InlineElements.maximumCapacity {
            self = .heap(UniqueArray<UInt8>(capacity: requiredCapacity))
        } else {
            self = .inline(InlineElements())
        }
    }

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

    @inlinable
    var count: Int {
        switch self {
        case .inline(let elements):
            return Int(elements.count)
        case .heap(let array):
            return array.count
        }
    }

    @inlinable
    var isEmpty: Bool {
        switch self {
        case .inline(let elements):
            return elements.isEmpty
        case .heap(let array):
            return array.isEmpty
        }
    }

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

    @inlinable
    mutating func append(_ element: UInt8) {
        switch consume self {
        case .inline(var elements):
            if elements.append(element) {
                self = .inline(elements)
            } else {
                var array = UniqueArray(
                    copying: elements,
                    capacity: InlineElements.maximumCapacity &+ 1
                )
                array.append(element)
                self = .heap(array)
            }
        case .heap(var array):
            array.append(element)
            self = .heap(array)
        }
    }

    @inlinable
    mutating func append(copying span: Span<UInt8>) {
        switch consume self {
        case .inline(var elements):
            let requiredCapacity = span.count + Int(elements.count)
            if requiredCapacity > InlineElements.maximumCapacity {
                var array = UniqueArray(copying: elements, capacity: requiredCapacity)
                array.append(copying: span)
                self = .heap(array)
            } else {
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

    @inlinable
    func withSpan<T>(_ block: (Span<UInt8>) -> T) -> T {
        switch self {
        case .inline(let elements):
            return elements.withSpan(block)
        case .heap(let array):
            return block(array.span)
        }
    }

    @inlinable
    mutating func append(
        exactExtraRequiredCapacity extraCapacity: Int,
        _ block: (inout OutputSpan<UInt8>) -> Void
    ) {
        /// Use heap if the required capacity requires so
        switch consume self {
        case .inline(let elements):
            let newCapacity = Int(elements.count) &+ extraCapacity
            if newCapacity > InlineElements.maximumCapacity {
                let array = UniqueArray(copying: elements, capacity: newCapacity)
                self = .heap(array)
            } else {
                self = .inline(elements)
            }
        case .heap(let array):
            self = .heap(array)
        }

        /// We know we have enough space, just append now
        switch consume self {
        case .inline(var elements):
            elements.edit { output in
                block(&output)
            }
            self = .inline(elements)
        case .heap(var array):
            /// TODO: might be able to use `edit` and skip the capacity check
            array.append(count: extraCapacity) { output in
                block(&output)
            }
            self = .heap(array)
        }
    }

    @inlinable
    mutating func append(copying utf8View: Unicode.Scalar.UTF8View) {
        self.append(exactExtraRequiredCapacity: utf8View.count) { output in
            for byte in utf8View {
                output.append(byte)
            }
        }
    }

    @inlinable
    mutating func insert(copying utf8View: Unicode.Scalar.UTF8View, at index: Int) {
        /// Use heap if the required capacity requires so
        switch consume self {
        case .inline(let elements):
            let newCapacity = Int(elements.count) &+ utf8View.count
            if newCapacity > InlineElements.maximumCapacity {
                let array = UniqueArray(copying: elements, capacity: newCapacity)
                self = .heap(array)
            } else {
                self = .inline(elements)
            }
        case .heap(let array):
            self = .heap(array)
        }

        /// We know we have enough space, just insert now
        switch consume self {
        case .inline(var elements):
            elements.uncheckedInsert(copying: utf8View, at: index)
            self = .inline(elements)
        case .heap(var array):
            array.insert(copying: utf8View, at: index)
            self = .heap(array)
        }
    }

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

        @inlinable
        static var maximumCapacity: Int {
            23
        }

        @inlinable
        static var countByteIndex: Int {
            Self.maximumCapacity
        }

        @inlinable
        init() {
            self.bits = (0, 0, 0)
        }

        @inlinable
        var count: UInt8 {
            withUnsafeBytes(of: bits.2) {
                $0[7]
            }
        }

        @inlinable
        var isEmpty: Bool {
            self.count == 0
        }

        @inlinable
        var isASCII: Bool {
            self.withSpan { $0.isASCII }
        }

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

        /// Returns `false` if the array is full.
        @inlinable
        mutating func append(_ element: UInt8) -> Bool {
            withUnsafeMutableBytes(of: &bits) { bitsPtr in
                let count = bitsPtr[Self.countByteIndex]
                if count == Self.maximumCapacity {
                    return false
                }

                bitsPtr[Int(count)] = element
                bitsPtr[Self.countByteIndex] = count &+ 1

                return true
            }
        }

        @inlinable
        mutating func removeAll() {
            self.bits = (0, 0, 0)
        }

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
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements) {
        self = elements.withSpan { String(_uncheckedAssumingValidUTF8: $0) }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension UniqueArray<UInt8> {
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
    @inlinable
    init(copying elements: borrowing TinyBuffer.InlineElements) {
        self = elements.withSpan { [UInt8](copying: $0) }
    }

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
    @inlinable
    init(consuming array: consuming TinyBuffer) {
        switch consume array {
        case .inline(let elements):
            self = .string(String(copying: elements))
        case .heap(let array):
            self = .bytes(array)
        }
    }
}
