@available(swiftIDNAApplePlatforms 10.15, *)
extension OutputSpan<UInt8> {
    @inlinable
    @_lifetime(&self)
    mutating func swift_idna_append(copying span: Span<UInt8>) {
        let usedCapacity = self.count
        let appendCount = span.count
        if appendCount == 0 { return }
        self.withUnsafeMutableBufferPointer { buffer, initializedCount in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.baseAddress.unsafelyUnwrapped.advanced(by: usedCapacity).copyMemory(
                    from: spanPtr.baseAddress.unsafelyUnwrapped,
                    byteCount: appendCount
                )
            }
            initializedCount = usedCapacity &+ appendCount
        }
    }

    @inlinable
    @_lifetime(&self)
    mutating func swift_idna_append(copying scalar: Unicode.Scalar) {
        for byte in scalar.utf8 {
            self.append(byte)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension OutputSpan where Element: BinaryInteger {
    @inlinable
    @_lifetime(&self)
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
