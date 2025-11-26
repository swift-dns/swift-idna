@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
protocol CompatibilityHelper: Sendable, ~Copyable {
    func makeString(
        unsafeUninitializedCapacity capacity: Int,
        initializingWith initializer: (
            _ appendFunction: (UInt8) -> Void
        ) throws -> Void
    ) rethrows -> String

    func makeString(
        _uncheckedAssumingValidUTF8 span: Span<UInt8>
    ) -> String

    func withSpan<T>(
        for bytes: [UInt8],
        _ body: (Span<UInt8>) throws -> T
    ) rethrows -> T

    func withSpan<T, E: Error>(
        for string: inout String,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T

    func withSpan<T, E: Error>(
        for substring: inout Substring,
        _ body: (Span<UInt8>) throws(E) -> T
    ) throws(E) -> T

    func isInNFC(span: Span<UInt8>) -> Bool

    func _uncheckedAssumingValidUTF8_ensureNFC(
        on bytes: inout [UInt8]
    )

    @_lifetime(copy span)
    func makeUnicodeScalarIterator(
        of span: Span<UInt8>
    ) -> any UnicodeScalarsIteratorProtocol & ~Escapable
}

@available(swiftIDNAApplePlatforms 10.15, *)
@usableFromInline
nonisolated let globalCompatibilityHelper: any CompatibilityHelper = {
    if #available(swiftIDNAApplePlatforms 26, *) {
        MacOS26CompatibilityHelper()
    } else if #available(swiftIDNAApplePlatforms 11, *) {
        MacOS11CompatibilityHelper()
    } else {
        MacOS10_15CompatibilityHelper()
    }
}()
