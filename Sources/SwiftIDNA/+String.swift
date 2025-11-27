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
        #if canImport(Darwin)
        String(unsafeUninitializedCapacity_Compatibility: self.utf8.count) { buffer in
            var idx = 0
            self._withNFCCodeUnits {
                buffer[idx] = $0
                idx &+= 1
            }
            return idx
        }
        #else
        String(unsafeUninitializedCapacity: self.utf8.count) { buffer in
            var idx = 0
            self._withNFCCodeUnits {
                buffer[idx] = $0
                idx &+= 1
            }
            return idx
        }
        #endif
    }

    /// Faster way is to use `utf8Span.checkForNFC(quickCheck: false)`
    var isInNFC_slow: Bool {
        self.unicodeScalars.allSatisfy(\.isASCII)
            || self.utf8.elementsEqual(self.nfcCodePoints)
    }

    @inlinable
    init(_uncheckedAssumingValidUTF8 span: Span<UInt8>) {
        let count = span.count
        #if canImport(Darwin)
        self.init(unsafeUninitializedCapacity_Compatibility: count) { buffer in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.copyMemory(from: spanPtr)
            }
            return count
        }
        #else
        self.init(unsafeUninitializedCapacity: count) { buffer in
            span.withUnsafeBytes { spanPtr in
                let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
                rawBuffer.copyMemory(from: spanPtr)
            }
            return count
        }
        #endif
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

    #if canImport(Darwin)
    @usableFromInline
    init(
        unsafeUninitializedCapacity_Compatibility capacity: Int,
        initializingWith initializer: (
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
            self.init(decoding: array, as: Unicode.UTF8.self)
        }
    }
    #endif
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
