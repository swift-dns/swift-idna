@available(swiftIDNAApplePlatforms 13, *)
extension IDNA {
    public enum ConversionResult {
        case noChangedNeeded
        case bytes([UInt8])
        case string(String)

        /// Collect this result into a new string.
        /// `nil` means no changes were needed.
        public func collect() -> String? {
            switch self {
            case .noChangedNeeded:
                return nil
            case .bytes(let bytes):
                return bytes.withSpan_Compatibility { span in
                    String(_uncheckedAssumingValidUTF8: span)
                }
            case .string(let string):
                return string
            }
        }

        /// Collect this result into a new string.
        /// `original` is returned if no changes were needed.
        public func collect(original: String) -> String {
            switch self {
            case .noChangedNeeded:
                return original
            case .bytes(let bytes):
                return bytes.withSpan_Compatibility { span in
                    String(_uncheckedAssumingValidUTF8: span)
                }
            case .string(let string):
                return string
            }
        }

        /// Perform an action using the span of the result.
        public func withSpan<T>(
            _ block: (Span<UInt8>) throws -> T,
            ifNotAvailable: () -> T
        ) rethrows -> T {
            switch self {
            case .noChangedNeeded:
                return ifNotAvailable()
            case .bytes(let bytes):
                return try bytes.withSpan_Compatibility {
                    return try block($0)
                }
            case .string(let string):
                if #available(swiftIDNAApplePlatforms 26, *) {
                    return try block(string.utf8Span.span)
                }
                var string = string
                return try string.withSpan_Compatibility_macOSUnder26 {
                    try block($0)
                }
            }
        }
    }
}
