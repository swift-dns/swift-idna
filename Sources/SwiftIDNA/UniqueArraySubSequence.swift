public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
struct UniqueArraySubSequence<Element>: ~Copyable {
    @usableFromInline
    var base: UniqueArray<Element>
    @usableFromInline
    var startIndex: Int

    @inlinable
    init(base: consuming UniqueArray<Element>, startIndex: Int) {
        self.base = base
        self.startIndex = startIndex
    }

    @inlinable
    var count: Int {
        self.base.count - self.startIndex
    }

    @inlinable
    mutating func append(_ element: Element) {
        self.base.append(element)
    }

    @inlinable
    mutating func append(copying span: Span<Element>) {
        self.base.append(copying: span)
    }

    @inlinable
    mutating func append(copying sequence: some Sequence<Element>) {
        self.base.append(copying: sequence)
    }

    @inlinable
    mutating func insert(copying collection: some Collection<Element>, at index: Int) {
        self.base.insert(copying: collection, at: self.startIndex + index)
    }

    @inlinable
    mutating func reserveCapacity(_ minimumCapacity: Int) {
        self.base.reserveCapacity(minimumCapacity)
    }

    @inlinable
    mutating func removeAll() {
        self.base.removeSubrange(startIndex..<self.base.count)
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension UniqueArraySubSequence<UInt8> {
    @inlinable
    var isASCII: Bool {
        var result: UInt8 = 0
        for idx in self.startIndex..<self.base.count {
            let byte = self.base[idx]
            result |= byte
        }
        return result <= 0x7F
    }
}
