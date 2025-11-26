@available(swiftIDNAApplePlatforms 10.15, *)
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
                return globalCompatibilityHelper.withSpan(for: bytes) { span in
                    globalCompatibilityHelper.makeString(_uncheckedAssumingValidUTF8: span)
                }
            case .string(let string):
                return string
            }
        }

        /// Perform an action using the span of the result.
        public func withSpan<T>(
            _ block: (Span<UInt8>) throws -> T,
            ifNotAvailable: () throws -> T
        ) rethrows -> T {
            switch self {
            case .noChangedNeeded:
                return try ifNotAvailable()
            case .bytes(let bytes):
                return try globalCompatibilityHelper.withSpan(for: bytes) {
                    try block($0)
                }
            case .string(let string):
                if #available(swiftIDNAApplePlatforms 26, *) {
                    return try block(string.utf8Span.span)
                }
                var string = string
                return try globalCompatibilityHelper.withSpan(for: &string) {
                    try block($0)
                }
            }
        }
    }
}
