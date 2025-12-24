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

/// A type that wraps some `UInt32`s that this library can guarantee to be valid Unicode scalars.
///
/// Unchecked `Sendable` because the pointer is guaranteed to be valid for the duration of the program execution.
/// That's also why we don't try to deallocate.
public struct IDNAUnicodeScalarView: SendableMetatype, @unchecked Sendable {
    @usableFromInline
    let pointer: UnsafeBufferPointer<UInt32>

    @inlinable
    init(staticPointer: UnsafeBufferPointer<UInt32>) {
        self.pointer = staticPointer
    }
}

/// MARK: +Equatable
extension IDNAUnicodeScalarView: Equatable {
    public static func == (lhs: IDNAUnicodeScalarView, rhs: IDNAUnicodeScalarView) -> Bool {
        lhs.count == rhs.count
            && lhs.count != 0
            && memcmp(
                /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
                lhs.pointer.baseAddress.unsafelyUnwrapped,
                rhs.pointer.baseAddress.unsafelyUnwrapped,
                lhs.count * 4
            ) == 0
    }
}

/// MARK: +Sequence
extension IDNAUnicodeScalarView: Sequence {
    public typealias Element = Unicode.Scalar

    @inlinable
    public var underestimatedCount: Int {
        self.count
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(base: self)
    }

    public struct Iterator: SendableMetatype, IteratorProtocol {
        @usableFromInline
        var base: IDNAUnicodeScalarView
        @usableFromInline
        var index: Int

        @inlinable
        init(base: IDNAUnicodeScalarView) {
            self.base = base
            self.index = 0
        }

        @inlinable
        public mutating func next() -> Unicode.Scalar? {
            guard self.index < self.base.count else { return nil }
            defer { self.index += 1 }
            let value = self.base.pointer.baseAddress.unsafelyUnwrapped
                .advanced(by: self.index).pointee
            /// `unsafelyUnwrapped` because the value is guaranteed to be a valid Unicode scalar.
            /// That's the whole point of the `IDNAUnicodeScalarView` type.
            return Unicode.Scalar(value).unsafelyUnwrapped
        }
    }
}

/// MARK: +Collection
extension IDNAUnicodeScalarView: Collection {
    public typealias Index = Int
    public typealias Indices = Range<Int>

    @inlinable
    public var count: Int {
        self.pointer.count
    }

    @inlinable
    public var isEmpty: Bool {
        self.count == 0
    }

    @inlinable
    public var first: Unicode.Scalar? {
        guard self.count > 0 else {
            return nil
        }
        return Unicode.Scalar(
            /// If the count is non-zero then the `UnsafeBufferPointer` guarantees there is a non-nil pointer.
            self.pointer.baseAddress.unsafelyUnwrapped.pointee
                /// `unsafelyUnwrapped` down there because the value is guaranteed to be a valid Unicode scalar.
                /// That's the whole point of the `IDNAUnicodeScalarView` type.
        ).unsafelyUnwrapped
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
    public func index(after i: Int) -> Int {
        let next = i + 1
        precondition(
            next >= 0 && next < self.count,
            "Index out of bounds: '\(next)', count: '\(self.count)'"
        )
        return next
    }

    @inlinable
    public func index(before i: Int) -> Int {
        let previous = i - 1
        precondition(
            previous >= 0 && previous < self.count,
            "Index out of bounds: '\(previous)', count: '\(self.count)'"
        )
        return previous
    }

    @inlinable
    public subscript(position: Int) -> Unicode.Scalar {
        _read {
            precondition(
                position >= 0 && position < self.count,
                "Index out of bounds: '\(position)', count: '\(self.count)'"
            )
            yield Unicode.Scalar(
                self.pointer.baseAddress.unsafelyUnwrapped.advanced(by: position).pointee
            ).unsafelyUnwrapped
        }
    }

    @inlinable
    public subscript(unchecked position: Int) -> Unicode.Scalar {
        _read {
            yield Unicode.Scalar(
                self.pointer.baseAddress.unsafelyUnwrapped.advanced(by: position).pointee
            ).unsafelyUnwrapped
        }
    }
}

/// MARK: +CustomStringConvertible
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
