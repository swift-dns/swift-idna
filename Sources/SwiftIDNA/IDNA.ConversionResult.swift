public import BasicContainers

@available(SwiftStdlib 5.1, *)
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
        public func withSpan<T, E: Error>(
            _ block: (Span<UInt8>) throws(E) -> T,
            ifNotAvailable: () throws(E) -> T
        ) throws(E) -> T {
            switch self {
            case .noChangesNeeded:
                return try ifNotAvailable()
            case .bytes(let bytes):
                return try block(bytes.span)
            case .string(let string):
                return try string.withSpan_Compatibility { (span) throws(E) in
                    try block(span)
                }
            }
        }
    }
}
