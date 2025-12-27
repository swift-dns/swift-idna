@available(swiftIDNAApplePlatforms 10.15, *)
extension OutputSpan<UInt8> {
    @inlinable
    #if swift(<6.3)
    @_lifetime(&self)
    #endif
    mutating func swift_idna_append(copying span: Span<UInt8>) {
        let appendCount = span.count
        if appendCount == 0 { return }
        let usedCapacity = self.count
        let capacity = self.capacity
        self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let range = Range<Int>(uncheckedBounds: (usedCapacity, capacity))
                let target = buffer.extracting(range)
                _ = target.initialize(fromContentsOf: spanPtr)
            }
            initializedCount = usedCapacity &+ appendCount
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension OutputSpan where Element: BinaryInteger {
    @inlinable
    #if swift(<6.3)
    @_lifetime(&self)
    #endif
    mutating func swift_idna_insert(_ element: Element, at index: Int) {
        let usedCapacity = self.count
        self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            if index < usedCapacity {
                let sourceRange = Range<Int>(uncheckedBounds: (index, usedCapacity))
                let source = buffer.extracting(sourceRange)
                let targetRange = Range<Int>(uncheckedBounds: (index &+ 1, usedCapacity &+ 1))
                let target = buffer.extracting(targetRange)
                let last = target.moveInitialize(fromContentsOf: source)
                assert(last == target.endIndex)
            }
            buffer.initializeElement(at: index, to: element)
            initializedCount = usedCapacity &+ 1
        }
    }
}
