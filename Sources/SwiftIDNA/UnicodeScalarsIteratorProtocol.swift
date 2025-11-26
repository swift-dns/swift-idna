@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
protocol UnicodeScalarsIteratorProtocol: ~Escapable {
    var currentCodeUnitOffset: Int { get }
    mutating func next() -> Unicode.Scalar?
    mutating func skipForward() -> Int
}

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UTF8Span.UnicodeScalarIterator: UnicodeScalarsIteratorProtocol {}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct UnicodeScalarViewCompatibilityIterator: UnicodeScalarsIteratorProtocol {
    var underlyingIterator: String.UnicodeScalarView.Iterator
    var currentCodeUnitOffset: Int

    mutating func next() -> Unicode.Scalar? {
        if let next = self.underlyingIterator.next() {
            self.currentCodeUnitOffset += next.utf8.count
            return next
        }
        return nil
    }

    mutating func skipForward() -> Int {
        if let next = self.underlyingIterator.next() {
            self.currentCodeUnitOffset += next.utf8.count
            return 1
        }
        return 0
    }
}
