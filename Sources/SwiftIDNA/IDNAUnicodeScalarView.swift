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
@available(swiftIDNAApplePlatforms 10.15, *)
public struct IDNAUnicodeScalarView: SendableMetatype, @unchecked Sendable {
    @usableFromInline
    let pointer: UnsafeBufferPointer<UInt8>

    @inlinable
    init(staticPointer: UnsafeBufferPointer<UInt8>) {
        self.pointer = staticPointer
    }
}

/// MARK: +Equatable
@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNAUnicodeScalarView: Equatable {
    public static func == (lhs: IDNAUnicodeScalarView, rhs: IDNAUnicodeScalarView) -> Bool {
        if lhs.pointer.count != rhs.pointer.count { return false }
        if lhs.pointer.count == 0 { return true }
        return memcmp(
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            lhs.pointer.baseAddress.unsafelyUnwrapped,
            rhs.pointer.baseAddress.unsafelyUnwrapped,
            lhs.pointer.count
        ) == 0
    }
}

/// MARK: +Sequence
@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNAUnicodeScalarView: Sequence {
    public typealias Element = Unicode.Scalar

    @inlinable
    public var underestimatedCount: Int {
        self.count
    }

    @inlinable
    public var count: Int {
        var iterator = UnicodeScalarIterator()
        var scalarsCount = 0
        while iterator.next(in: self.pointer.span) != nil {
            scalarsCount &+= 1
        }
        return scalarsCount
    }

    @inlinable
    public var utf8BytesCount: Int {
        self.pointer.count
    }

    @inlinable
    public var isEmpty: Bool {
        self.pointer.count == 0
    }

    @inlinable
    public var first: Unicode.Scalar? {
        guard self.pointer.count > 0 else {
            return nil
        }
        var iterator = UnicodeScalarIterator()
        return iterator.next(in: self.pointer.span)
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
        0..<self.count
    }

    @inlinable
    public var utf8BytesSpan: Span<UInt8> {
        self.pointer.span
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
            self.iterator.next(in: self.base.pointer.span)
        }
    }
}

/// MARK: +CustomStringConvertible
@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNAUnicodeScalarView: CustomStringConvertible {
    @inlinable
    public var description: String {
        var result = "IDNAUnicodeScalarView(["
        let elementsCount = self.count
        result.reserveCapacity(result.count + elementsCount * 6 + 2)
        let lastIdx = elementsCount &- 1
        for idx in self.indices {
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            let value = self.pointer.baseAddress.unsafelyUnwrapped.advanced(by: idx).pointee
            result.append("0x\(String(value, radix: 16, uppercase: true))")
            if idx != lastIdx {
                result.append(", ")
            }
        }
        result.append("])")
        return result
    }
}

/// MARK: +CustomDebugStringConvertible
@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNAUnicodeScalarView: CustomDebugStringConvertible {
    @inlinable
    public var debugDescription: String {
        var result =
            "IDNAUnicodeScalarView(pointer: \(self.pointer.debugDescription), count: \(self.count), elements: ["
        let elementsCount = self.count
        result.reserveCapacity(result.count + elementsCount * 6 + 2)
        let lastIdx = elementsCount &- 1
        for idx in self.indices {
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            let value = self.pointer.baseAddress.unsafelyUnwrapped.advanced(by: idx).pointee
            result.append("0x\(String(value, radix: 16, uppercase: true))")
            if idx != lastIdx {
                result.append(", ")
            }
        }
        result.append("])")
        return result
    }
}
