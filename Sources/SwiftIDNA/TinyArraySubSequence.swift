@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct TinyArraySubSequence: ~Copyable {
    @usableFromInline
    var base: TinyArray
    @usableFromInline
    var startIndex: Int

    @inlinable
    init(base: consuming TinyArray, startIndex: Int) {
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
            let range = Range<Int>(uncheckedBounds: (self.startIndex, self.base.count))
            return block(span.extracting(unchecked: range))
        }
    }

    @inlinable
    mutating func append(_ element: UInt8) {
        self.base.append(element)
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

    @inlinable
    mutating func preferablyReserveCapacity(_ minimumCapacity: Int) {
        self.base.preferablyReserveCapacity(minimumCapacity)
    }

    @inlinable
    mutating func removeAll() {
        let range = Range<Int>(uncheckedBounds: (self.startIndex, self.base.count))
        self.base.removeSubrange(range)
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension TinyArraySubSequence {
    @inlinable
    var isASCII: Bool {
        self.withSpan { $0.isASCII }
    }
}
