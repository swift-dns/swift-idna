@available(swiftIDNAApplePlatforms 10.15, *)
extension String {
    var nfcCodePoints: [UInt8] {
        var codePoints = [UInt8]()
        codePoints.reserveCapacity(self.utf8.count)
        self._withNFCCodeUnits {
            codePoints.append($0)
        }
        return codePoints
    }

    var asNFC: String {
        String(
            unsafeUninitializedCapacity_Compatibility: self.utf8.count
        ) { handle in
            self._withNFCCodeUnits {
                handle.append($0)
            }
        }
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    var isInNFC_slow: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @inlinable
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        self.init(unsafeUninitializedCapacity_Compatibility: span.count) { handle in
            span.withUnsafeBytes { spanPtr in
                handle.copyMemory(from: spanPtr)
            }
        }
    }

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

    @usableFromInline
    struct BytesHandle: ~Copyable, ~Escapable {
        @usableFromInline
        var buffer: UnsafeMutableBufferPointer<UInt8>
        @usableFromInline
        var count: Int = 0

        @inlinable
        init(buffer: UnsafeMutableBufferPointer<UInt8>) {
            self.buffer = buffer
        }

        @inlinable
        @_lifetime(&self)
        mutating func append(_ byte: UInt8) {
            self.buffer[self.count] = byte
            self.count &+= 1
        }

        @inlinable
        @_lifetime(&self)
        mutating func copyMemory(from source: UnsafeRawBufferPointer) {
            let pointer = UnsafeMutableRawBufferPointer(self.buffer)
            pointer.copyMemory(from: source)
            self.count &+= source.count
        }

        @inlinable
        consuming func consumeReturningInitializedCount() -> Int {
            self.count
        }
    }

    @usableFromInline
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingWith initializer: (_ handle: inout BytesHandle) throws -> Void
    ) rethrows {
        if #available(swiftIDNAApplePlatforms 11, *) {
            try self.init(unsafeUninitializedCapacity: capacity) { stringBuffer in
                var handle = BytesHandle(buffer: stringBuffer)
                try initializer(&handle)
                return handle.consumeReturningInitializedCount()
            }
        } else {
            let array = try [UInt8].init(
                unsafeUninitializedCapacity: capacity
            ) { buffer, initializedCount in
                var handle = BytesHandle(buffer: buffer)
                try initializer(&handle)
                initializedCount = handle.consumeReturningInitializedCount()
            }
            self.init(decoding: array, as: Unicode.UTF8.self)
        }
    }
}

@available(swiftIDNAApplePlatforms 10.15, *)
extension Substring {
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
