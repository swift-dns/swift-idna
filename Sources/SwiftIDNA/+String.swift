public import BasicContainers

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

    @inlinable
    func isEqualToNFCCodePointsOfSelf() -> Bool {
        var copy = self
        return copy.withSpan_Compatibility { span -> Bool in
            var idx = 0
            var isInNFC = true
            let currentCount = span.count

            self._withNFCCodeUnits { utf8Byte in
                if !isInNFC { return }

                if currentCount <= idx || utf8Byte != span[unchecked: idx] {
                    isInNFC = false
                    return
                }

                idx &+= 1
            }

            return isInNFC
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

    @usableFromInline
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        if #available(swiftIDNAApplePlatforms 26, *) {
            let utf8Span = UTF8Span(unchecked: span)
            self.init(copying: utf8Span)
        } else if #available(swiftIDNAApplePlatforms 11, *) {
            self.init(unsafeUninitializedCapacity: span.count) { buffer in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    rawBuffer.copyMemory(from: spanPtr)
                }
                return span.count
            }
        } else {
            let array = [UInt8].init(
                unsafeUninitializedCapacity: span.count
            ) { buffer, initializedCount in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    rawBuffer.copyMemory(from: spanPtr)
                }
                initializedCount = span.count
            }
            self.init(decoding: array, as: UTF8.self)
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
