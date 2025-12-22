public import BasicContainers

#if os(Windows)
public import func ucrt.memcmp
#elseif canImport(Darwin)
public import func Darwin.memcmp
#elseif canImport(Glibc)
@preconcurrency public import func Glibc.memcmp
#elseif canImport(Musl)
@preconcurrency public import func Musl.memcmp
#elseif canImport(Bionic)
@preconcurrency public import func Bionic.memcmp
#elseif canImport(WASILibc)
@preconcurrency public import func WASILibc.memcmp
#else
#error("The SwiftIDNA.+String module was unable to identify your C library.")
#endif

@available(swiftIDNAApplePlatforms 10.15, *)
extension String {
    @inlinable
    var nfcCodePoints: UniqueArray<UInt8> {
        var codePoints = UniqueArray<UInt8>(capacity: self.utf8.count)
        self._withNFCCodeUnits {
            codePoints.append($0)
        }
        return codePoints
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    @inlinable
    var isInNFC_slow: Bool {
        mutating get {
            if self.isEmpty || Self.isASCII(self.utf8) { return true }

            let nfcCodePoints = self.nfcCodePoints
            let count = nfcCodePoints.count
            if count != self.utf8.count {
                return false
            }
            return nfcCodePoints.span.withUnsafeBytes { nfcPtr in
                self.withSpan_Compatibility { selfSpan in
                    selfSpan.withUnsafeBytes { selfPtr in
                        let nfcPtrBase: UnsafeRawPointer? = nfcPtr.baseAddress
                        let selfPtrBase: UnsafeRawPointer? = selfPtr.baseAddress
                        return memcmp(
                            nfcPtrBase.unsafelyUnwrapped,
                            selfPtrBase.unsafelyUnwrapped,
                            count
                        ) == 0
                    }
                }
            }
        }
    }

    @inlinable
    static func isASCII(_ utf8View: String.UTF8View) -> Bool {
        var result: UInt8 = 0
        for byte in utf8View {
            result |= byte
        }
        return result <= 0x7F
    }

    @inlinable
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        let count = span.count
        self.init(unsafeUninitializedCapacity_Compatibility: count) { buffer in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.copyMemory(from: spanPtr)
            }
            return count
        }
    }

    @usableFromInline
    mutating func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try body(self.utf8Span.span)
        }
        do {
            return try self.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }

    #if canImport(Darwin)
    @usableFromInline
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingUTF8With initializer: (
            _ buffer: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int
    ) rethrows {
        if #available(swiftIDNAApplePlatforms 11, *) {
            try self.init(unsafeUninitializedCapacity: capacity) { buffer in
                try initializer(buffer)
            }
        } else {
            let array = try [UInt8].init(
                unsafeUninitializedCapacity: capacity
            ) { buffer, initializedCount in
                initializedCount = try initializer(buffer)
            }
            self.init(decoding: array, as: UTF8.self)
        }
    }
    #else
    /// @_transparent helps mitigate some performance regressions on Linux that happened when
    /// moving from directly using the underlying initializer, to this compatibility initializer.
    @_transparent
    @inlinable
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingWith initializer: (
            _ buffer: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int
    ) rethrows {
        try self.init(unsafeUninitializedCapacity: capacity) { buffer in
            try initializer(buffer)
        }
    }
    #endif
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension Substring {
    @usableFromInline
    mutating func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        if #available(swiftIDNAApplePlatforms 26, *) {
            return try body(self.utf8Span.span)
        }
        do {
            return try self.withUTF8 { buffer in
                try body(buffer.span)
            }
        } catch let error as E {
            throw error
        } catch {
            fatalError("Unexpected error: \(String(reflecting: error))")
        }
    }
}
