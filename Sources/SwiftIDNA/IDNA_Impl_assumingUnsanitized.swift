/// The implementations below in this file, do not pass the un-sanitized user-input `span` to
/// any functions outside this file.
/// The other functions outside this file can assume they are operating on UTF8-only bytes.
/// Still, the punycode decode needs to take into account the possibility of decoding non-UTF8.
@available(SwiftStdlib 5.1, *)
extension IDNA {
    /// `ToASCII` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToASCII
    @inlinable
    func _toASCII(span: Span<UInt8>) throws(CollectedMappingErrors) -> ConversionResult {
        switch IDNA.performByteCheck(on: span) {
        case .containsOnlyIDNANoOpCharacters:
            return .noChangesNeeded
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            /// At this point we know the bytes are ASCII, so we know they are valid UTF8.
            let string = convertToLowercasedASCII(_uncheckedAssumingValidUTF8: span)
            return .string(string)
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainNameSpan: span)

        // 1.
        let result = TinyBuffer.withInlineAllocation { convertedBytes -> ConversionResult in
            TinyBuffer.withInlineAllocation { processedBytes -> ConversionResult in

                /// Main `Processing` IDNA implementation.
                /// https://www.unicode.org/reports/tr46/#Processing
                /// 1. Map
                self.mapToIDNAMappings_Scalar(
                    span: span,
                    into: &convertedBytes,
                    errors: &errors
                )

                /// Notice no `span` (direct user input) is passed to this function.
                self._mainProcessing(
                    reuseBuffer: &convertedBytes,
                    output: &processedBytes,
                    errors: &errors
                )

                /// Notice no `span` (direct user input) is passed to this function.
                return self._toASCII(
                    convertedBytes: &convertedBytes,
                    processedBytes: &processedBytes,
                    errors: &errors
                )
            }
        }

        if let errors = errors.collect() {
            throw errors
        }

        return result
    }

    /// `ToUnicode` IDNA implementation.
    /// https://www.unicode.org/reports/tr46/#ToUnicode
    @inlinable
    func _toUnicode(span: Span<UInt8>) throws(CollectedMappingErrors) -> ConversionResult {
        switch IDNA.performByteCheck(on: span) {
        case .containsOnlyIDNANoOpCharacters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                return .noChangesNeeded
            }
        case .onlyNeedsLowercasingOfUppercasedASCIILetters:
            if !span.containsIDNADomainNameMarkerLabelPrefix {
                /// At this point we know the bytes are ASCII, so we know they are valid UTF8.
                let string = convertToLowercasedASCII(_uncheckedAssumingValidUTF8: span)
                return .string(string)
            }
        case .mightChangeAfterIDNAConversion:
            break
        }

        var errors = MappingErrors(domainNameSpan: span)

        // 1.
        let result = TinyBuffer.withInlineAllocation { reuseBuffer -> ConversionResult in
            TinyBuffer.withInlineAllocation { utf8Bytes -> ConversionResult in

                /// Main `Processing` IDNA implementation.
                /// https://www.unicode.org/reports/tr46/#Processing
                /// 1. Map
                self.mapToIDNAMappings_SIMD(
                    span: span,
                    into: &reuseBuffer,
                    errors: &errors
                )

                /// Notice no `span` (direct user input) is passed to this function.
                self._mainProcessing(
                    reuseBuffer: &reuseBuffer,
                    output: &utf8Bytes,
                    errors: &errors
                )

                return utf8Bytes.takeAsConversionResult()
            }
        }

        // 2.
        if let errors = errors.collect() {
            throw errors
        }

        return result
    }

    @inlinable
    @inline(__always)
    func mapToIDNAMappings_Scalar(
        span: Span<UInt8>,
        into newBytes: inout TinyBuffer,
        errors: inout MappingErrors
    ) {
        var requiredCapacity = 0

        var unicodeScalarsIterator = UnicodeScalarIterator()

        while let (uncheckedScalar, range) = unicodeScalarsIterator.nextWithRange(in: span) {
            /// Invalid scalar values resolve to `ignored`, so they contribute no capacity.
            /// The error for them is appended in the second pass below.
            let mapping = IDNAMapping.for(uncheckedScalar: uncheckedScalar)
            let isMapped = mapping.tag == .mapped
            let isIgnored = mapping.tag == .ignored
            let mappedScalarsCount = mapping.mappedScalars.utf8BytesSpan.count
            let _toAdd = isIgnored ? 0 : range.count
            let toAdd = isMapped ? mappedScalarsCount : _toAdd
            requiredCapacity &+= toAdd
        }

        /// I'm expecting this to be empty at this point, nothing special.
        /// Tests will immediately crash if this is not the case.
        assert(newBytes.isEmpty)

        unicodeScalarsIterator = UnicodeScalarIterator()

        /// Reserve the exact required capacity up front so we can skip further capacity checks
        /// because we're guaranteed to have enough capacity.
        newBytes.append(extraRequiredCapacity: requiredCapacity) { output in
            while let (uncheckedScalar, range) = unicodeScalarsIterator.nextWithRange(in: span) {
                guard let scalar = Unicode.Scalar(uncheckedScalar) else {
                    errors.append(
                        .labelContainsInvalidUnicode(
                            uncheckedScalar,
                            label: String(span: span)
                        )
                    )
                    continue
                }

                let mapping = IDNAMapping.for(scalar: scalar)
                if mapping.tag == .ignored {
                    continue
                }
                let isMapped = mapping.tag == .mapped
                let scalarBytesSpan = unsafe span.extracting(unchecked: range)
                let mappedScalarsSpan = mapping.mappedScalars.utf8BytesSpan
                let span = isMapped ? mappedScalarsSpan : scalarBytesSpan
                output.swift_idna_append(copying: span)
            }
        }
    }

    @inlinable
    @inline(__always)
    func mapToIDNAMappings_SIMD(
        span: Span<UInt8>,
        into newBytes: inout TinyBuffer,
        errors: inout MappingErrors
    ) {
        let count = span.count

        assert(newBytes.isEmpty)

        SIMDUnicodeScalarDecoder.withTemporaryDecoder { decoder in
            /// Process windows of size `SIMDUnicodeScalarDecoder.windowSize`, one by one.
            var startIdx = 0
            while startIdx < count {
                decoder.decodeNextWindow(of: span, startIdx: startIdx)
                let scalarCount = decoder.scalarCount

                var requiredCapacity = 0
                let range = unsafe Range<Int>(uncheckedBounds: (0, scalarCount))
                for scalarIdx in range {
                    let offset = decoder.scalarStartOffset(at: scalarIdx)
                    let scalarUTF8Length = decoder.scalarUTF8Length(at: scalarIdx)
                    let uncheckedScalar = unsafe decoder.uncheckedScalarValues[unchecked: offset]

                    /// Invalid scalar values resolve to `ignored`, so they contribute no capacity.
                    /// The error for them is appended in the second pass below.
                    let mapping = IDNAMapping.for(uncheckedScalar: uncheckedScalar)
                    let isMapped = mapping.tag == .mapped
                    let isIgnored = mapping.tag == .ignored
                    let mappedScalarsCount = mapping.mappedScalars.utf8BytesSpan.count
                    let _toAdd = isIgnored ? 0 : scalarUTF8Length
                    let toAdd = isMapped ? mappedScalarsCount : _toAdd
                    requiredCapacity &+= toAdd
                }

                newBytes.append(extraRequiredCapacity: requiredCapacity) { output in
                    for scalarIdx in range {
                        let offset = decoder.scalarStartOffset(at: scalarIdx)
                        let scalarUTF8Length = decoder.scalarUTF8Length(at: scalarIdx)
                        let uncheckedScalar = unsafe decoder.uncheckedScalarValues[
                            unchecked: offset
                        ]

                        guard let scalar = Unicode.Scalar(uncheckedScalar) else {
                            errors.append(
                                .labelContainsInvalidUnicode(
                                    uncheckedScalar,
                                    label: String(span: span)
                                )
                            )
                            continue
                        }

                        let mapping = IDNAMapping.for(scalar: scalar)
                        if mapping.tag == .ignored {
                            continue
                        }
                        let isMapped = mapping.tag == .mapped
                        let scalarStartIdx = startIdx &+ offset
                        let scalarRange = unsafe Range<Int>(
                            uncheckedBounds: (scalarStartIdx, scalarStartIdx &+ scalarUTF8Length)
                        )
                        let scalarBytesSpan = unsafe span.extracting(unchecked: scalarRange)
                        let mappedScalarsSpan = mapping.mappedScalars.utf8BytesSpan
                        let span = isMapped ? mappedScalarsSpan : scalarBytesSpan
                        output.swift_idna_append(copying: span)
                    }
                }
                startIdx &+= decoder.windowEndOffset()
            }
        }
    }

    /// Converts the given span to lowercase ASCII.
    @usableFromInline
    func convertToLowercasedASCII(_uncheckedAssumingValidUTF8 span: Span<UInt8>) -> String {
        let count = span.count
        return unsafe String(unsafeUninitializedCapacity_Compatibility: count) { buffer in
            var idx = 0
            while idx < count {
                unsafe buffer[idx] = span[unchecked: idx].toLowercasedASCIILetter()
                idx &+= 1
            }
            return count
        }
    }
}
