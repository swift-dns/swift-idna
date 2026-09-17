import BasicContainers
import SwiftIDNA
import Testing

@Suite
struct IDNATests {
    typealias ConversionResult = IDNA.ConversionResult
    typealias CollectedMappingErrors = IDNA.CollectedMappingErrors
    typealias IDNAResolvedFunctionType = (IDNA) -> (
        ([UInt8]) throws(CollectedMappingErrors) -> [UInt8]
    )

    @available(SwiftStdlib 6.2, *)
    @Test func `UniqueArray allocates as expected`() {
        var array = UniqueArray<UInt8>(minimumCapacity: 24)
        for _ in 0..<25 {
            array.append(0)
        }
        #expect(array.capacity == TINY_ARRAY__UNIQUE_ARRAY_ALLOCATION_THRESHOLD)
    }

    static func makeBytesFunction(
        source: [UInt8],
        idnaFunction:
            @escaping (IDNA) -> ((Span<UInt8>) throws(CollectedMappingErrors) -> ConversionResult)
    ) -> IDNAResolvedFunctionType {
        { idna in
            { bytes throws(CollectedMappingErrors) -> [UInt8] in
                try bytes.withUnsafeBufferPointer {
                    bytesPtr throws(CollectedMappingErrors) -> [UInt8] in
                    let span = unsafe bytesPtr.span
                    let function = idnaFunction(idna)
                    let result = try function(span)
                    let resultBytes = result.collectBytes() ?? source
                    return resultBytes
                }
            }
        }
    }

    static func makeStringFunction(
        idnaFunction:
            @escaping (IDNA) -> ((String) throws(CollectedMappingErrors) -> String)
    ) -> IDNAResolvedFunctionType {
        { idna in
            { bytes throws(CollectedMappingErrors) -> [UInt8] in
                /// For the very few invalid-UTF8 cases, these string representation will be inaccurate
                /// but that's fine as long as the tests pass.
                /// Invalid UTF8 can't/shouldn't make it into `String` anyway.
                let inputString = String(decoding: bytes, as: UTF8.self)
                let function = idnaFunction(idna)
                let result = try function(inputString)
                let bytes = [UInt8](result.utf8)
                return bytes
            }
        }
    }

    /// For debugging you can choose a specific test case based on its index. For example
    /// for index 5101, use `@Test(arguments: IDNATestV2Case.enumeratedAllCases()[5101...5101])`.
    @Test(arguments: IDNATestV2Case.enumeratedAllCases())
    func `run IDNATestV2Suite against toASCII Span<UInt8> function`(
        index: Int,
        arg: IDNATestV2Case
    ) throws {
        var idna = IDNA(configuration: .mostStrict)
        /// Because ToASCII will go through ToUnicode too
        var statuses = arg.toUnicodeStatus + arg.toAsciiNStatus
        try runTestCase(
            idna: &idna,
            function: Self.makeBytesFunction(source: arg.source, idnaFunction: IDNA.toASCII),
            source: arg.source,
            expected: arg.toAsciiN,
            remainingStatuses: &statuses
        )
    }

    /// For debugging you can choose a specific test case based on its index. For example
    /// for index 5101, use `@Test(arguments: IDNATestV2Case.enumeratedAllCases()[5101...5101])`.
    @Test(arguments: IDNATestV2Case.enumeratedAllCases())
    func `run IDNATestV2Suite against toASCII String function`(
        index: Int,
        arg: IDNATestV2Case
    ) throws {
        var idna = IDNA(configuration: .mostStrict)
        /// Because ToASCII will go through ToUnicode too
        var statuses = arg.toUnicodeStatus + arg.toAsciiNStatus
        try runTestCase(
            idna: &idna,
            function: Self.makeStringFunction(idnaFunction: IDNA.toASCII),
            source: arg.source,
            expected: arg.toAsciiN,
            remainingStatuses: &statuses
        )
    }

    /// For debugging you can choose a specific test case based on its index. For example
    /// for index 5101, use `@Test(arguments: IDNATestV2Case.enumeratedAllCases()[5101...5101])`.
    @Test(arguments: IDNATestV2Case.enumeratedAllCases())
    func `run IDNATestV2Suite against toUnicode Span<UInt8> function`(
        index: Int,
        arg: IDNATestV2Case
    ) throws {
        var idna = IDNA(configuration: .mostStrict)
        var statuses = arg.toUnicodeStatus
        try runTestCase(
            idna: &idna,
            function: Self.makeBytesFunction(source: arg.source, idnaFunction: IDNA.toUnicode),
            source: arg.source,
            expected: arg.toUnicode,
            remainingStatuses: &statuses
        )
    }

    /// For debugging you can choose a specific test case based on its index. For example
    /// for index 5101, use `@Test(arguments: IDNATestV2Case.enumeratedAllCases()[5101...5101])`.
    @Test(arguments: IDNATestV2Case.enumeratedAllCases())
    func `run IDNATestV2Suite against toUnicode String function`(
        index: Int,
        arg: IDNATestV2Case
    ) throws {
        var idna = IDNA(configuration: .mostStrict)
        var statuses = arg.toUnicodeStatus
        try runTestCase(
            idna: &idna,
            function: Self.makeStringFunction(idnaFunction: IDNA.toUnicode),
            source: arg.source,
            expected: arg.toUnicode,
            remainingStatuses: &statuses
        )
    }

    /// Runs the certain IDNA function using the source string and the makes sure it produces the
    /// expected result according the the IDNA test V2 suite.
    ///
    /// How it works:
    /// 1. If `expected` is `nil`, then it runs the `function` using `source` and makes sure the
    ///    conversion is not successful or it simply results in the same `source` string.
    /// 2. If `expected` is not `nil`, runs the `function` using `source`. Then:
    /// 3. If there are no errors thrown by `function`, then checks if the result is
    ///     equal to `expected`.
    /// 4. If there are errors thrown by `function`, then it disables one of the thrown errors
    ///    by setting the corresponding flag in `idna.configuration` to a value that would disable
    ///    that certain error. Then jumps back to step 1.
    ///
    /// This process continues until either the `function` succeeds or runs out of tries to make.
    func runTestCase(
        idna: inout IDNA,
        function: IDNAResolvedFunctionType,
        source: [UInt8],
        expected: [UInt8]?,
        remainingStatuses: inout [IDNATestV2Case.Status],
        tryNumber: Int = 0
    ) throws {
        if tryNumber > 10 {
            Issue.record(
                "Too many tries. Remaining statuses: \(remainingStatuses.debugDescription), idna.configuration: \(idna.configuration)"
            )
            return
        }

        guard let expected = expected else {
            var convertedSource = source
            do {
                convertedSource = try function(idna)(convertedSource)
                if convertedSource != source,
                    convertedSource.uppercased() != source.uppercased()
                {
                    Issue.record(
                        "Didn't expect a converted value for source: \(source.debugDescription) in the first try, but got: \(convertedSource.debugDescription)"
                    )
                }
            } catch {
                /// good
            }
            return
        }

        do {
            var convertedSource = source
            convertedSource = try function(idna)(convertedSource)
            #expect(
                convertedSource.debugDescription == expected.debugDescription,
                "tries: \(tryNumber)"
            )
        } catch let idnaError {
            /// If there are multiple errors, we need to disable one of them and try again.
            /// We try to do `ignoresInvalidPunycode = true` last, because it single-handedly
            /// disables a lot of errors.
            /// We also try to disable `P4` as late as possible because it'll disable checkHyphens
            /// too, other than enabling `ignoresInvalidPunycode`.
            guard
                let error = idnaError.errors
                    .sorted(by: { l, _ in !l.disablingWillRequireIgnoringInvalidPunycode })
                    .sorted(by: { l, _ in !(l.correspondingIDNAStatus == .P4) })
                    .first
            else {
                fatalError("No error element found in errors: \(idnaError)")
            }
            if let correspondingStatus = error.correspondingIDNAStatus {
                /// Can't make the tests pass by disabling "invalid unicode" errors
                if remainingStatuses.contains(.V7) {
                    return
                }
                #expect(
                    remainingStatuses.containsRelatedStatusCode(to: correspondingStatus),
                    "Current error: \(error), errors: \(idnaError.errors)"
                )
            }
            guard
                error.disable(
                    inConfiguration: &idna.configuration,
                    removingFrom: &remainingStatuses
                )
            else {
                Issue.record(
                    "Failed to disable error: \(error), idna.configuration: \(idna.configuration)"
                )
                return
            }
            try self.runTestCase(
                idna: &idna,
                function: function,
                source: source,
                expected: expected,
                remainingStatuses: &remainingStatuses,
                tryNumber: tryNumber + 1
            )
        }
    }
}

extension IDNA.ConversionResult {
    func collectBytes() -> [UInt8]? {
        switch self {
        case .noChangesNeeded:
            return nil
        case .bytes(let bytes):
            return [UInt8](copying: bytes.span)
        case .string(let string):
            return [UInt8](string.utf8)
        }
    }
}

extension [UInt8] {
    fileprivate func uppercased() -> [UInt8] {
        self.map {
            if $0 >= 97, $0 <= 122 {
                return $0 - 32
            } else {
                return $0
            }
        }
    }
}
