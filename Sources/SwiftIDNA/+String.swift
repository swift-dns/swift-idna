@available(SwiftStdlib 5.1, *)
extension String {
    /// Initializes a `String` by assuming the given span contains valid UTF-8 bytes.
    @usableFromInline
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        if #available(SwiftStdlib 6.2, *) {
            let utf8Span = unsafe UTF8Span(unchecked: span)
            self.init(copying: utf8Span)
        } else if #available(SwiftStdlib 5.3, *) {
            self.init(unsafeUninitializedCapacity: span.count) { buffer in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    unsafe rawBuffer.copyMemory(from: spanPtr)
                }
                return span.count
            }
        } else {
            let array = unsafe [UInt8].init(
                unsafeUninitializedCapacity: span.count
            ) { buffer, initializedCount in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    unsafe rawBuffer.copyMemory(from: spanPtr)
                }
                initializedCount = span.count
            }
            self.init(decoding: array, as: UTF8.self)
        }
    }

    /// Initializes a `String` by assuming the given span contains any bytes (including invalid UTF-8 bytes).
    @usableFromInline
    init(span: Span<UInt8>) {
        /// String(copying:) is faster but doesn't do UTF8 repairing.
        if #available(SwiftStdlib 6.2, *), span.checkUTF8() {
            let utf8Span = unsafe UTF8Span(unchecked: span)
            self.init(copying: utf8Span)
        } else if #available(SwiftStdlib 5.3, *) {
            self.init(unsafeUninitializedCapacity: span.count) { buffer in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    unsafe rawBuffer.copyMemory(from: spanPtr)
                }
                return span.count
            }
        } else {
            let array = unsafe [UInt8].init(
                unsafeUninitializedCapacity: span.count
            ) { buffer, initializedCount in
                span.withUnsafeBytes { spanPtr in
                    let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                    unsafe rawBuffer.copyMemory(from: spanPtr)
                }
                initializedCount = span.count
            }
            self.init(decoding: array, as: UTF8.self)
        }
    }

    /// Calls `body` with a `Span` of this String's utf8 bytes.
    @inlinable
    @inline(always)
    func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        /// Fast path: Currently always the case for non-Darwin.
        /// On Darwin, always the case unless for some objc-bridged strings.
        if let fastResult = self.utf8.withContiguousStorageIfAvailable({ buffer in
            Result(catching: { () throws(E) -> T in
                try body(unsafe buffer.span)
            })
        }) {
            return try fastResult.get()
        }

        return try self.withSpan_Compatibility_SlowPath(body)
    }

    /// This function can only be reached on Darwin and only for some objc-bridged strings.
    /// Therefore it's not worth inlining. As a matter of fact it's worth not inlining it at all.
    @usableFromInline
    @inline(never)
    func withSpan_Compatibility_SlowPath<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        /// Same availability guard as `utf8Span` has in swift repo.
        /// The symbol is available there but will just abort.
        #if !(os(watchOS) && _pointerBitWidth(_32))
        if #available(SwiftStdlib 6.2, *) {
            return try body(self.utf8Span.span)
        }
        #endif

        var copy = self
        let result = copy.withUTF8 { buffer in
            Result(catching: { () throws(E) -> T in
                try body(unsafe buffer.span)
            })
        }
        return try result.get()
    }

    #if canImport(Darwin)
    @usableFromInline
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingUTF8With initializer: (
            _ buffer: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int
    ) rethrows {
        if #available(SwiftStdlib 5.3, *) {
            try self.init(unsafeUninitializedCapacity: capacity) { buffer in
                unsafe try initializer(buffer)
            }
        } else {
            let array = unsafe try [UInt8].init(
                unsafeUninitializedCapacity: capacity
            ) { buffer, initializedCount in
                initializedCount = unsafe try initializer(buffer)
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

@available(SwiftStdlib 5.1, *)
extension Substring {
    /// Calls `body` with a `Span` of this Substring's utf8 bytes.
    @inlinable
    @inline(always)
    func withSpan_Compatibility<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        /// Fast path: Currently always the case for non-Darwin.
        /// On Darwin, always the case unless for some objc-bridged strings.
        if let fastResult = unsafe self.utf8.withContiguousStorageIfAvailable({ buffer in
            Result(catching: { () throws(E) -> T in
                try body(unsafe buffer.span)
            })
        }) {
            return try fastResult.get()
        }

        return try self.withSpan_Compatibility_SlowPath(body)
    }

    /// This function can only be reached on Darwin and only for some objc-bridged strings.
    /// Therefore it's not worth inlining. As a matter of fact it's worth not inlining it at all.
    @usableFromInline
    @inline(never)
    func withSpan_Compatibility_SlowPath<T, E: Error>(
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T {
        /// Same availability guard as `utf8Span` has in swift repo.
        /// The symbol is available there but will just abort.
        #if !(os(watchOS) && _pointerBitWidth(_32))
        if #available(SwiftStdlib 6.2, *) {
            return try body(self.utf8Span.span)
        }
        #endif

        var copy = self
        let result = copy.withUTF8 { buffer in
            Result(catching: { () throws(E) -> T in
                try body(unsafe buffer.span)
            })
        }
        return try result.get()
    }
}
