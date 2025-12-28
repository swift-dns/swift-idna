public import BasicContainers

@available(swiftIDNAApplePlatforms 10.15, *)
extension IDNA {
    @nonexhaustive
    public enum ConversionResult: ~Copyable {
        case noChangesNeeded
        case bytes(UniqueArray<UInt8>)
        case string(String)

        /// Collect this result into a new string.
        /// `nil` means no changes were needed and the original string was all-good.
        @inlinable
        public func collect() -> String? {
            switch self {
            case .noChangesNeeded:
                return nil
            case .bytes(let bytes):
                return String(_uncheckedAssumingValidUTF8: bytes.span)
            case .string(let string):
                return string
            }
        }

        /// Perform an action using the span of the result.
        /// `ifNotAvailable` is called when no changes were needed and the original string was all-good.
        @inlinable
        public func withSpan<T>(
            _ block: (Span<UInt8>) throws -> T,
            ifNotAvailable: () throws -> T
        ) rethrows -> T {
            switch self {
            case .noChangesNeeded:
                return try ifNotAvailable()
            case .bytes(let bytes):
                return try block(bytes.span)
            case .string(let string):
                var string = string
                return try string.withSpan_Compatibility {
                    try block($0)
                }
            }
        }
    }
}
