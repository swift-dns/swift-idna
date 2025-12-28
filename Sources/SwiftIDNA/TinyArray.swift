public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
enum TinyArray: ~Copyable {
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
    mutating func append(_ element: UInt8) {
        switch consume self {
        case .inline(var elements):
            if elements.append(element) {
                self = .inline(elements)
            } else {
                var array = elements.collectAsUniqueArray(
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
    func withSpan(_ block: (Span<UInt8>) -> Void) {
        switch self {
        case .inline(let elements):
            elements.withSpan(block)
        case .heap(let array):
            block(array.span)
        }
    }

    @inlinable
    mutating func append(
        exactExtraRequiredCapacity extraCapacity: Int,
        _ block: (inout OutputSpan<UInt8>) -> Void
    ) {
        switch consume self {
        case .inline(let elements):
            let newCapacity = Int(elements.count) &+ extraCapacity
            if newCapacity > InlineElements.maximumCapacity {
                let array = elements.collectAsUniqueArray(capacity: newCapacity)
                self = .heap(array)
            } else {
                self = .inline(elements)
            }
        case .heap(let array):
            self = .heap(array)
        }

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

    @inlinable
    func copyAsNormalArray() -> [UInt8] {
        switch self {
        case .inline(let elements):
            return elements.copyAsNormalArray()
        case .heap(let array):
            return [UInt8](copying: array.span)
        }
    }

    @inlinable
    consuming func asConversionResult() -> IDNA.ConversionResult {
        switch consume self {
        case .inline(let elements):
            return .string(elements.collectAsString())
        case .heap(let array):
            return .bytes(array)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension TinyArray {
    @usableFromInline
    struct InlineElements: ~Copyable {
        @usableFromInline
        typealias BitPattern = (UInt64, UInt64)

        @usableFromInline
        var bits: BitPattern

        @inlinable
        static var maximumCapacity: Int {
            15
        }

        @inlinable
        init() {
            self.bits = (0, 0)
        }

        @inlinable
        var count: UInt8 {
            withUnsafeBytes(of: bits.1) {
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
                    let count = bitsPtr[15]
                    let bytesSpan = bitsBytes.span.extracting(unchecked: 0..<Int(count))
                    return try body(bytesSpan)
                }
            }
        }

        /// Returns `false` if the array is full.
        @inlinable
        mutating func append(_ element: UInt8) -> Bool {
            withUnsafeMutableBytes(of: &bits) {
                let count = $0[15]
                if count == Self.maximumCapacity {
                    return false
                }

                $0[Int(count)] = element
                $0[15] = count &+ 1

                return true
            }
        }

        @inlinable
        mutating func removeAll() {
            self.bits = (0, 0)
        }

        @inlinable
        mutating func edit(_ block: (inout OutputSpan<UInt8>) -> Void) {
            withUnsafeMutableBytes(of: &self.bits) { bitsPtr in
                bitsPtr.withMemoryRebound(to: UInt8.self) { bitsBytes in
                    let count = Int(bitsPtr[15])
                    let mutableBytes = bitsBytes.extracting(0..<Self.maximumCapacity)
                    var span = OutputSpan(buffer: mutableBytes, initializedCount: count)

                    block(&span)

                    let newCount = span.finalize(for: mutableBytes)
                    span = OutputSpan()
                    bitsPtr[15] = UInt8(newCount)
                }
            }
        }

        @inlinable
        func copyAsNormalArray() -> [UInt8] {
            self.withSpan { [UInt8](copying: $0) }
        }

        @inlinable
        func collectAsUniqueArray(capacity: Int) -> UniqueArray<UInt8> {
            assert(capacity > Self.maximumCapacity)

            var array = UniqueArray<UInt8>(capacity: capacity)

            array.edit { output in
                output.withUnsafeMutableBufferPointer { outputPtr, initializedCount in
                    withUnsafeBytes(of: bits) { bitsPtr in
                        bitsPtr.withMemoryRebound(to: UInt8.self) { bitsBytes in
                            let count = Int(bitsPtr[15])
                            let elements = bitsBytes.extracting(0..<count)
                            /// Last bit is the counts bit
                            _ = outputPtr.initialize(fromContentsOf: elements)
                            initializedCount = count
                        }
                    }
                }
            }

            return array
        }

        @inlinable
        func collectAsString() -> String {
            /// `elements` can only contain 15 bytes. String also holds 15 bytes inline so
            /// we can freely just pass the bytes to the string initializer.
            assert(self.count <= Self.maximumCapacity)

            return self.withSpan { String(_uncheckedAssumingValidUTF8: $0) }
        }

        @inlinable
        mutating func _uncheckedAssumingValidUTF8_ensureNFC() {
            if self.isEmpty || self.isASCII { return }

            let string = self.collectAsString()

            self.removeAll()
            self.edit { output in
                string._withNFCCodeUnits { utf8Byte in
                    output.append(utf8Byte)
                }
            }
        }
    }
}
