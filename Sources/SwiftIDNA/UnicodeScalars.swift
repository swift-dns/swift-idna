/// A type that wraps some `UInt32`s that this library can guarantee to be valid Unicode scalars.
/// Conforms to all of the same protocols as `String.UnicodeScalarView` does.
public struct IDNAUnicodeScalarsView<ScalarsBuffer>
where
    ScalarsBuffer:
        Sequence
        & Collection
        & BidirectionalCollection
        & RangeReplaceableCollection,
    ScalarsBuffer.Element == UInt32,
    ScalarsBuffer.Index == Int
{
    @usableFromInline
    var underlying: ScalarsBuffer

    @inlinable
    init(__uncheckedElements elements: ScalarsBuffer) {
        self.underlying = elements
    }

    @inlinable
    public init() {
        self.underlying = .init()
    }
}

/// MARK: +Sendable
extension IDNAUnicodeScalarsView: Sendable where ScalarsBuffer: Sendable {}

/// MARK: +SendableMetatype
extension IDNAUnicodeScalarsView: SendableMetatype where ScalarsBuffer: SendableMetatype {}

/// MARK: +Equatable
extension IDNAUnicodeScalarsView: Equatable where ScalarsBuffer: Equatable {}

/// MARK: +Hashable
extension IDNAUnicodeScalarsView: Hashable where ScalarsBuffer: Hashable {}

/// MARK: +Sequence
extension IDNAUnicodeScalarsView: Sequence {
    public typealias Element = Unicode.Scalar

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(__uncheckedIterator: underlying.makeIterator())
    }

    public struct Iterator: IteratorProtocol {
        @usableFromInline
        var underlying: ScalarsBuffer.Iterator

        @inlinable
        init(__uncheckedIterator iterator: ScalarsBuffer.Iterator) {
            self.underlying = iterator
        }

        @inlinable
        public mutating func next() -> Unicode.Scalar? {
            underlying.next().map {
                Unicode.Scalar($0).unsafelyUnwrapped
            }
        }
    }
}

extension IDNAUnicodeScalarsView.Iterator: Sendable where ScalarsBuffer.Iterator: Sendable {}

/// MARK: +Collection, +BidirectionalCollection, +RangeReplaceableCollection
extension IDNAUnicodeScalarsView: Collection, BidirectionalCollection, RangeReplaceableCollection {
    public typealias Index = ScalarsBuffer.Index
    public typealias Indices = ScalarsBuffer.Indices
    public typealias SubSequence = IDNAUnicodeScalarsView<ScalarsBuffer.SubSequence>

    @inlinable
    public var startIndex: Int {
        self.underlying.startIndex
    }

    @inlinable
    public var endIndex: Int {
        self.underlying.endIndex
    }

    @inlinable
    public var indices: ScalarsBuffer.Indices {
        self.underlying.indices
    }

    @inlinable
    public func index(after i: Array<UInt32>.Index) -> Array<UInt32>.Index {
        self.underlying.index(after: i)
    }

    @inlinable
    public func index(before i: Array<UInt32>.Index) -> Array<UInt32>.Index {
        self.underlying.index(before: i)
    }

    @inlinable
    public subscript(position: Self.Index) -> Unicode.Scalar {
        _read {
            yield Unicode.Scalar(self.underlying[position]).unsafelyUnwrapped
        }
    }

    @inlinable
    public subscript(bounds: Range<Self.Index>) -> Self.SubSequence {
        IDNAUnicodeScalarsView<ScalarsBuffer.SubSequence>(
            __uncheckedElements: self.underlying[bounds]
        )
    }

    @inlinable
    public mutating func replaceSubrange(
        _ subrange: Range<Self.Index>,
        with newElements: some Collection<Unicode.Scalar>
    ) {
        self.underlying.replaceSubrange(
            subrange,
            with: newElements.lazy.map(\.value)
        )
    }

    @inlinable
    public init(repeating repeatedValue: Self.Element, count: Int) {
        self.underlying = .init(repeating: repeatedValue.value, count: count)
    }

    @inlinable
    public init(_ elements: some Sequence<Unicode.Scalar>) {
        self.underlying = .init(elements.lazy.map(\.value))
    }

    @inlinable
    public mutating func reserveCapacity(_ n: Int) {
        self.underlying.reserveCapacity(n)
    }

    @inlinable
    public mutating func append(_ newElement: Self.Element) {
        self.underlying.append(newElement.value)
    }

    @inlinable
    public mutating func append(contentsOf newElements: some Sequence<Unicode.Scalar>) {
        self.underlying.append(contentsOf: newElements.lazy.map(\.value))
    }

    @inlinable
    public mutating func insert(_ newElement: Self.Element, at i: Self.Index) {
        self.underlying.insert(newElement.value, at: i)
    }

    @inlinable
    public mutating func insert(
        contentsOf newElements: some Collection<Unicode.Scalar>,
        at i: Self.Index
    ) {
        self.underlying.insert(contentsOf: newElements.lazy.map(\.value), at: i)
    }

    @discardableResult
    @inlinable
    public mutating func remove(at i: Self.Index) -> Self.Element {
        Unicode.Scalar(self.underlying.remove(at: i)).unsafelyUnwrapped
    }

    @inlinable
    public mutating func removeSubrange(_ bounds: Range<Self.Index>) {
        self.underlying.removeSubrange(bounds)
    }

    @discardableResult
    @inlinable
    public mutating func removeFirst() -> Self.Element {
        Unicode.Scalar(self.underlying.removeFirst()).unsafelyUnwrapped
    }

    @inlinable
    public mutating func removeFirst(_ k: Int) {
        self.underlying.removeFirst(k)
    }

    @inlinable
    public mutating func removeAll(keepingCapacity keepCapacity: Bool) {
        self.underlying.removeAll(keepingCapacity: keepCapacity)
    }

    @inlinable
    public mutating func removeAll(
        where shouldBeRemoved: (Self.Element) throws -> Bool
    ) rethrows {
        try self.underlying.removeAll {
            try shouldBeRemoved(Unicode.Scalar($0).unsafelyUnwrapped)
        }
    }
}

/// MARK: +CustomStringConvertible
extension IDNAUnicodeScalarsView: CustomStringConvertible {
    @inlinable
    public var description: String {
        String(describing: self.underlying)
    }
}

/// MARK: +CustomDebugStringConvertible
extension IDNAUnicodeScalarsView: CustomDebugStringConvertible {
    @inlinable
    public var debugDescription: String {
        String(reflecting: self.underlying)
    }
}

/// MARK: +CustomReflectable
extension IDNAUnicodeScalarsView: CustomReflectable {
    @inlinable
    public var customMirror: Mirror {
        Mirror(self, unlabeledChildren: self.underlying)
    }
}
