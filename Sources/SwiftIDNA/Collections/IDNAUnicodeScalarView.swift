#if os(Windows)
import ucrt
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Bionic)
@preconcurrency import Bionic
#elseif canImport(WASILibc)
@preconcurrency import WASILibc
#else
#error("The SwiftIDNA.IDNAUnicodeScalarView module was unable to identify your C library.")
#endif

/// A type that wraps some `UInt8`s that this library can guarantee to be valid Unicode scalars.
///
/// Unchecked `Sendable` because the pointer is guaranteed to be valid for the duration of the program execution.
/// That's also why we don't try to deallocate.
@available(SwiftStdlib 5.1, *)
@safe public struct IDNAUnicodeScalarView: SendableMetatype, @unchecked Sendable {
    @usableFromInline
    let pointer: UnsafeBufferPointer<UInt8>

    @inlinable
    init(staticPointer: UnsafeBufferPointer<UInt8>) {
        unsafe self.pointer = staticPointer
    }
}

/// MARK: +Equatable
@available(SwiftStdlib 5.1, *)
extension IDNAUnicodeScalarView: Equatable {
    public static func == (lhs: IDNAUnicodeScalarView, rhs: IDNAUnicodeScalarView) -> Bool {
        if unsafe lhs.pointer.count != rhs.pointer.count { return false }
        if unsafe lhs.pointer.count == 0 { return true }
        return unsafe memcmp(
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            lhs.pointer.baseAddress.unsafelyUnwrapped,
            rhs.pointer.baseAddress.unsafelyUnwrapped,
            lhs.pointer.count
        ) == 0
    }
}

/// MARK: +Sequence
@available(SwiftStdlib 5.1, *)
extension IDNAUnicodeScalarView: Sequence {
    public typealias Element = Unicode.Scalar

    /// Exact count of the code points in this view.
    @inlinable
    public var underestimatedCount: Int {
        self.count
    }

    /// Count of the code points in this view.
    @inlinable
    public var count: Int {
        self.reduce(into: 0) { result, _ in
            result &+= 1
        }
    }

    @inlinable
    public var isEmpty: Bool {
        unsafe self.pointer.count == 0
    }

    @inlinable
    public var startIndex: Int {
        0
    }

    @inlinable
    public var endIndex: Int {
        self.count
    }

    @inlinable
    public var indices: Range<Int> {
        unsafe Range(uncheckedBounds: (0, self.count))
    }

    /// Span of the raw utf8 bytes in this view.
    @inlinable
    public var utf8BytesSpan: Span<UInt8> {
        unsafe self.pointer.span
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(base: self)
    }

    public struct Iterator: SendableMetatype, IteratorProtocol {
        @usableFromInline
        var base: IDNAUnicodeScalarView
        @usableFromInline
        var iterator: UnicodeScalarIterator

        @inlinable
        init(base: IDNAUnicodeScalarView) {
            self.base = base
            self.iterator = UnicodeScalarIterator()
        }

        @inlinable
        public mutating func next() -> Unicode.Scalar? {
            guard let uncheckedScalar = unsafe self.iterator.next(in: self.base.pointer.span) else {
                return nil
            }
            return unsafe Unicode.Scalar(uncheckedScalar).unsafelyUnwrapped
        }
    }
}

/// MARK: +CustomStringConvertible
@available(SwiftStdlib 5.1, *)
extension IDNAUnicodeScalarView: CustomStringConvertible {
    @inlinable
    public var description: String {
        var result = "IDNAUnicodeScalarView(["
        let elementsCount = self.count
        result.reserveCapacity(result.count + elementsCount * 6 + 2)
        let lastIdx = elementsCount &- 1
        for idx in self.indices {
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            let value = unsafe self.pointer.baseAddress.unsafelyUnwrapped.advanced(by: idx).pointee
            result.append("0x\(String(value, radix: 16, uppercase: true))")
            if idx != lastIdx {
                result.append(", ")
            }
        }
        result.append("])")
        return result
    }
}
