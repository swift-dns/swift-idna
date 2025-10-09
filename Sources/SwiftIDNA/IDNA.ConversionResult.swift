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

        /// This function below would require us to be able to tie `bytes` lifetime to the `UTF8Span` lifetime.
        /// Which is currently not possible.

        // /// Collect this result into the provided UTF8Span.
        // @available(swiftIDNAApplePlatforms 26, *)
        // public func collect(into utf8Span: inout UTF8Span) {
        //     switch self {
        //     case .noChangedNeeded:
        //         return
        //     case .bytes(let bytes):
        //         bytes.withSpan_Compatibility { span in
        //             utf8Span = UTF8Span(unchecked: span)
        //         }
        //     case .string(let string):
        //         domainName = string
        //     }
        // }
    }
}
