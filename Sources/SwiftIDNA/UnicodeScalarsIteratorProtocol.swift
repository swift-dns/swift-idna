@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
protocol UnicodeScalarsIteratorProtocol: ~Escapable {
    @inlinable
    var currentCodeUnitOffset: Int { get }
    @inlinable
    mutating func next() -> Unicode.Scalar?
    @inlinable
    mutating func skipForward() -> Int
}

@available(swiftIDNAApplePlatforms 26, *)
extension UTF8Span.UnicodeScalarIterator: UnicodeScalarsIteratorProtocol {}

@available(swiftIDNAApplePlatforms 10.15, *)
struct UnicodeScalarViewCompatibilityIterator: UnicodeScalarsIteratorProtocol {
    @usableFromInline
    var underlyingIterator: String.UnicodeScalarView.Iterator
    @usableFromInline
    var currentCodeUnitOffset: Int

    @inlinable
    mutating func next() -> Unicode.Scalar? {
        if let next = self.underlyingIterator.next() {
            self.currentCodeUnitOffset += next.utf8.count
            return next
        }
        return nil
    }

    @inlinable
    mutating func skipForward() -> Int {
        if let next = self.underlyingIterator.next() {
            self.currentCodeUnitOffset += next.utf8.count
            return 1
        }
        return 0
    }
}
