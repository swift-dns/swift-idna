public import CSwiftIDNA

public enum IDNAMapping: Equatable {
    public enum IDNA2008Status {
        case NV8
        case XV8
        case none
    }

    case valid(IDNA2008Status)
    case mapped(IDNAUnicodeScalarView)
    case deviation(IDNAUnicodeScalarView)
    case disallowed
    case ignored
}

extension IDNAMapping {
    /// Look up IDNA mapping for a given Unicode scalar
    /// - Parameter scalar: The Unicode scalar to look up
    /// - Returns: The corresponding `IDNAMapping` value
    @inlinable
    public static func `for`(scalar: Unicode.Scalar) -> IDNAMapping {
        /// `unsafelyUnwrapped` because the C function is guaranteed to return a non-nil pointer.
        /// There are also extensive tests in IDNATests for this function.
        let result = cswift_idna_mapping_lookup(scalar.value).unsafelyUnwrapped.pointee
        switch result.type {
        case 0:
            let status: IDNAMapping.IDNA2008Status =
                switch result.status {
                case 0: .NV8
                case 1: .XV8
                case 2: .none
                default:
                    fatalError(
                        "Unexpected IDNAMapping.CSwiftIDNA2008Status: \(result.status) for type \(result.type)"
                    )
                }
            return .valid(status)
        case 1:
            /// These are guaranteed to be valid Unicode scalars.
            /// We wrap these in a view-like type (IDNAUnicodeScalarView) to ensure we don't need
            /// allocations while having a way to guarantee they are valid Unicode scalars to users.
            let scalars = IDNAUnicodeScalarView(
                staticPointer: UnsafeBufferPointer(
                    start: result.mapped_unicode_scalars,
                    count: Int(result.mapped_count)
                )
            )
            return .mapped(scalars)
        case 2:
            /// These are guaranteed to be valid Unicode scalars.
            /// We wrap these in a view-like type (IDNAUnicodeScalarView) to ensure we don't need
            /// allocations while having a way to guarantee they are valid Unicode scalars to users.
            let scalars = IDNAUnicodeScalarView(
                staticPointer: UnsafeBufferPointer(
                    start: result.mapped_unicode_scalars,
                    count: Int(result.mapped_count)
                )
            )
            return .deviation(scalars)
        case 3:
            return .disallowed
        case 4:
            return .ignored
        default:
            fatalError("Unexpected CSwiftIDNAMappingResultType: \(result.type)")
        }
    }
}
