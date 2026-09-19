#if !($Embedded || os(WASI))
internal import Highway
#endif

/// [Punycode: A Bootstring encoding of Unicode for Internationalized Domain Names in Applications (IDNA)](https://datatracker.ietf.org/doc/html/rfc3492)
@available(SwiftStdlib 5.1, *)
@usableFromInline
package enum Punycode {
    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Parameter values for Punycode](https://datatracker.ietf.org/doc/html/rfc3492#section-5)
    ///
    /// To support 32-bit platforms, we use `UInt32` instead of `Int` throughout this implementation.
    @usableFromInline
    enum Constants {
        @inlinable
        static var base: UInt32 {
            36
        }

        @inlinable
        static var tMin: UInt32 {
            1
        }

        @inlinable
        static var tMax: UInt32 {
            26
        }

        @inlinable
        static var skew: UInt32 {
            38
        }

        @inlinable
        static var damp: UInt32 {
            700
        }

        @inlinable
        static var initialBias: UInt32 {
            72
        }

        @inlinable
        static var initialN: UInt32 {
            128
        }

        /// A valid IDNA label cannot need more digits than this for a single delta, so a longer
        /// run of digits is always invalid input.
        ///
        /// Per RFC 3492 section 6.4 a valid label's delta never exceeds
        /// `(0x10FFFF - initialN) * (63 + 1)`. `adapt` is monotonic in its delta, so evaluating it
        /// at that maximum is what bounds the bias, giving `163`.
        ///
        /// The positions a delta occupies at a given bias are `min { j : delta < M(j) }`, over the
        /// cumulative capacities `M(1) = t(1)` and `M(j + 1) = M(j) + t(j + 1) * W(j + 1)` built
        /// from the weights of section 3.3, `W(1) = 1` and `W(j + 1) = W(j) * (base - t(j))`.
        /// Evaluating that at the maximum delta for every bias in `0...163` peaks at 8, reached at
        /// the small biases where `t(j)` is already clamped to `tMax` so each position only
        /// multiplies the capacity by `base - tMax`.
        @inlinable
        static var maximumDigitsPerDeltaPlusOne: UInt32 {
            9
        }

        /// `encode` emits one more digit after its loop, and unlike `decode` it has no way to
        /// reject its input: nothing bounds the label length before it runs, so it can be handed a
        /// delta no valid label could produce. Its loop therefore has to be wide enough for any
        /// `UInt32` delta rather than only the valid ones, and by the same derivation as above the
        /// widest of those occupies 10 positions, at bias 14.
        @inlinable
        static var maximumEncodedDigitsPerDelta: UInt32 {
            10
        }
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Encoding procedure](https://datatracker.ietf.org/doc/html/rfc3492#section-6.3)
    /// Returns true if successful and false if conversion failed.
    ///
    /// This function uses unchecked/unsafe handling of some values. These are all safe.
    /// This function is heavily tested with 6400 tests from Unicode's IDNA V2 test suite.
    ///
    /// This function does not do overflow handling because based on RFC 3492,
    /// overflows are not possible for what matches the description of Swift's `Unicode.Scalar` type:
    ///
    /// https://datatracker.ietf.org/doc/html/rfc3492#section-5:
    /// ```text
    /// Although the only restriction Punycode imposes on the input integers
    /// is that they be nonnegative, these parameters are especially designed
    /// to work well with Unicode [UNICODE] code points, which are integers
    /// in the range 0..10FFFF (but not D800..DFFF, which are reserved for
    /// use by the UTF-16 encoding of Unicode).
    /// ```
    ///
    /// https://datatracker.ietf.org/doc/html/rfc3492#section-6.4
    /// ```text
    /// For IDNA, 26-bit unsigned integers are sufficient to handle all valid
    /// IDNA labels without overflow, because any string that needed a 27-bit
    /// delta would have to exceed either the code point limit (0..10FFFF) or
    /// the label length limit (63 characters).  However, overflow handling
    /// is necessary because the inputs are not necessarily valid IDNA
    /// labels.
    /// ```
    ///
    /// `outputBufferForReuse` is used as a performance optimization.
    /// You should pass 1 shared `outputBufferForReuse` for all labels, so this function can
    /// reset and reuse the buffer.
    /// You can use use the `outputBufferForReuse` after the function returns.
    @inlinable
    package static func encode(
        inputBytesSpan: Span<UInt8>,
        outputBufferForReuse output: inout TinyBuffer,
        decodedUnicodeScalars: borrowing DecodedUnicodeScalars.Subsequence
    ) {
        var n = Constants.initialN
        var delta: UInt32 = 0
        var bias = Constants.initialBias
        output.removeAll(keepingCapacity: true)

        for idx in inputBytesSpan.indices {
            let byte = inputBytesSpan[idx]
            if byte.isASCII {
                output.append(byte)
            }
        }
        let b = UInt32(output.count)
        var h = b

        if !output.isEmpty {
            output.append(UInt8.asciiHyphenMinus)
        }

        var loopIdx = h
        let scalarsCount = decodedUnicodeScalars.count
        while loopIdx < scalarsCount {
            let m = Punycode.smallestScalar(atLeast: n, in: decodedUnicodeScalars)

            delta &+= ((m &- n) &* (h &+ 1))

            n = m
            var idx = 0
            while idx < scalarsCount {
                let codePoint = decodedUnicodeScalars[idx]
                if codePoint.value < n || codePoint.isASCII {
                    delta &+= 1
                }

                if codePoint.value == n {
                    var q = delta

                    for idx in 1..<Constants.maximumEncodedDigitsPerDelta {
                        let k = Constants.base &* idx

                        let t =
                            if k <= (bias &+ Constants.tMin) {
                                Constants.tMin
                            } else if k >= (bias &+ Constants.tMax) {
                                Constants.tMax
                            } else {
                                k &- bias
                            }

                        if q < t {
                            break
                        }

                        let digit = t &+ ((q &- t) % (Constants.base &- t))
                        /// Logically this is safe because we know that digit is in the range 0...35
                        /// There are also extensive tests for this in the IDNATests.swift.
                        output.append(Punycode.uncheckedMapDigitToUTF8Byte(digit))

                        q = (q &- t) / (Constants.base &- t)
                    }
                    /// Logically this is safe because we know that digit is in the range 0...35
                    /// There are also extensive tests for this in the IDNATests.swift.
                    output.append(Punycode.uncheckedMapDigitToUTF8Byte(q))

                    bias = adapt(delta: delta, codePointCount: h &+ 1, isFirstTime: h == b)
                    delta = 0
                    h &+= 1
                    /// Skip one unicode scalar
                    loopIdx &+= 1
                }
                idx &+= 1
            }
            delta &+= 1
            n &+= 1
        }
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Decoding procedure](https://datatracker.ietf.org/doc/html/rfc3492#section-6.2)
    /// Returns true if successful and false if conversion failed.
    ///
    /// This function uses unchecked/unsafe handling of some values. These are all safe.
    /// This function is heavily tested with 6400 tests from Unicode's IDNA V2 test suite.
    ///
    /// This function does not do overflow handling because based on RFC 3492,
    /// overflows are not possible for what matches the description of Swift's `Unicode.Scalar` type:
    ///
    /// https://datatracker.ietf.org/doc/html/rfc3492#section-5:
    /// ```text
    /// Although the only restriction Punycode imposes on the input integers
    /// is that they be nonnegative, these parameters are especially designed
    /// to work well with Unicode [UNICODE] code points, which are integers
    /// in the range 0..10FFFF (but not D800..DFFF, which are reserved for
    /// use by the UTF-16 encoding of Unicode).
    /// ```
    ///
    /// https://datatracker.ietf.org/doc/html/rfc3492#section-6.4
    /// ```text
    /// For IDNA, 26-bit unsigned integers are sufficient to handle all valid
    /// IDNA labels without overflow, because any string that needed a 27-bit
    /// delta would have to exceed either the code point limit (0..10FFFF) or
    /// the label length limit (63 characters).  However, overflow handling
    /// is necessary because the inputs are not necessarily valid IDNA
    /// labels.
    /// ```
    ///
    /// Returns true if successful, in which case `outputBuffer` will have been populated.
    @inlinable
    static func decode(
        _uncheckedAssumingValidUTF8 inputBytesSpan: Span<UInt8>,
        scalarsForReuse scalars: inout LinkedList<UnicodeScalarValue>,
        outputBuffer output: inout TinyBufferSubsequence
    ) -> Bool {
        var inputBytesSpan = inputBytesSpan
        var n = Constants.initialN
        var i: UInt32 = 0
        var bias = Constants.initialBias
        var utf8Count = 0

        scalars.removeAll()

        if let utf8Idx = inputBytesSpan.lastIndex(of: .asciiHyphenMinus) {
            let afterDelimiterIdx = utf8Idx &+ 1
            let range = unsafe Range<Int>(uncheckedBounds: (0, utf8Idx))
            let basicBytesSpan = unsafe inputBytesSpan.extracting(unchecked: range)

            guard basicBytesSpan.isASCII else {
                return false
            }

            for idx in basicBytesSpan.indices {
                let byte = UInt32(unsafe basicBytesSpan[unchecked: idx])
                scalars.append(UnicodeScalarValue(_uncheckedAssumingValid: byte))
            }
            utf8Count = basicBytesSpan.count

            let inputBytesRange = unsafe Range<Int>(
                uncheckedBounds: (afterDelimiterIdx, inputBytesSpan.count)
            )
            inputBytesSpan = unsafe inputBytesSpan.extracting(unchecked: inputBytesRange)
        }

        var offset = 0
        while offset != inputBytesSpan.count {
            let oldi = i
            var w: UInt32 = 1
            var isDeltaComplete = false

            for idx in 1..<Constants.maximumDigitsPerDeltaPlusOne {
                let k = Constants.base &* idx

                guard offset < inputBytesSpan.count else {
                    return false
                }

                let byte = unsafe inputBytesSpan[unchecked: offset]
                guard let _digit = Punycode.mapCodePointToDigit(byte) else {
                    return false
                }
                let digit = UInt32(_digit)
                offset &+= 1

                i &+= (digit &* w)

                let t =
                    if k <= (bias &+ Constants.tMin) {
                        Constants.tMin
                    } else if k >= (bias &+ Constants.tMax) {
                        Constants.tMax
                    } else {
                        k &- bias
                    }

                if digit < t {
                    isDeltaComplete = true
                    break
                }

                w = w &* (Constants.base &- t)
            }

            guard isDeltaComplete else {
                return false
            }

            let outputCountPlusOne = UInt32(scalars.count) &+ 1
            bias = adapt(
                delta: i &- oldi,
                codePointCount: outputCountPlusOne,
                isFirstTime: oldi == 0
            )
            n = n &+ (i / outputCountPlusOne)
            i = i % outputCountPlusOne
            /// Check if n is basic (aka ASCII), a surrogate, or above the maximum scalar value.
            guard !n.isASCII, let scalar = UnicodeScalarValue(n) else {
                return false
            }

            scalars.insert(scalar, at: Int(i))
            utf8Count &+= UTF8BytesIterator.utf8Length(uncheckedScalar: n)

            i &+= 1
        }

        let scalarsIterator = scalars.makeIterator()
        output.append(extraRequiredCapacity: utf8Count) { output in
            var scalarsIterator = scalarsIterator
            while let scalar = scalarsIterator.next() {
                let (utf8Length, bytes) = UTF8BytesIterator.encode(
                    uncheckedScalar: scalar.value
                )
                output.swift_idna_append(encodedScalar: bytes, count: utf8Length)
            }
        }

        return true
    }

    /// The smallest non-ASCII scalar that is not below `n`, or `UInt32.max` if there is none.
    @usableFromInline
    /// Intentionally `@inline(__always)`, so Swift compiler doesn't inconsistently complain about usage of both it and `@usableFromInline`.
    @inline(__always)
    static func smallestScalar(
        atLeast n: UInt32,
        in decodedUnicodeScalars: borrowing DecodedUnicodeScalars.Subsequence
    ) -> UInt32 {
        #if $Embedded || os(WASI)
        return smallestScalar_SlowPath(atLeast: n, in: decodedUnicodeScalars)
        #else
        return smallestScalar_FastPath(atLeast: n, in: decodedUnicodeScalars)
        #endif
    }

    #if $Embedded || os(WASI)
    /// Intentionally `@inline(never)`, so LLVM auto-vectorizes it.
    /// Otherwise it refuses to, with the following analysis which I couldn't easily bypass:
    /// ```
    /// [Analysis] NonReductionValueUsedOutsideLoop
    ///   loop not vectorized: value that could not be identified as reduction is used outside the loop
    /// ```
    @inline(never)
    static func smallestScalar_SlowPath(
        atLeast n: UInt32,
        in decodedUnicodeScalars: borrowing DecodedUnicodeScalars.Subsequence
    ) -> UInt32 {
        let scalarsCount = decodedUnicodeScalars.count
        guard scalarsCount > 0 else {
            return .max
        }

        return unsafe decodedUnicodeScalars.withUnsafeScalarValues { values in
            var smallest = UInt32.max
            for idx in 0..<scalarsCount {
                let value = unsafe values[idx]
                smallest = min(smallest, value < n ? .max : value)
            }
            return smallest
        } ?? .max
    }
    #else
    @inline(always)
    static func smallestScalar_FastPath(
        atLeast n: UInt32,
        in decodedUnicodeScalars: borrowing DecodedUnicodeScalars.Subsequence
    ) -> UInt32 {
        let scalarsCount = decodedUnicodeScalars.count
        guard scalarsCount > 0 else {
            return .max
        }

        let laneCount = HighwayUInt32.laneCount
        let identity = HighwayUInt32.repeating(.max)
        let threshold = HighwayUInt32.repeating(n)
        var accumulator = identity

        return unsafe decodedUnicodeScalars.withUnsafeScalarValues { values in
            var idx = 0
            while idx &+ laneCount <= scalarsCount {
                let loaded = unsafe HighwayUInt32.load(from: values + idx)
                let isBelow = HighwayUInt32.lessThan(loaded, threshold)
                accumulator = HighwayUInt32.minimum(
                    accumulator,
                    HighwayUInt32.selecting(isBelow, identity, loaded)
                )
                idx &+= laneCount
            }
            if idx < scalarsCount {
                let loaded = unsafe HighwayUInt32.loadFirst(
                    from: values + idx,
                    count: scalarsCount &- idx
                )
                /// `loadFirst` zero-fills the lanes past `count`, and zero is below `n`, so the
                /// padding selects the identity and cannot win the reduction.
                let isBelow = HighwayUInt32.lessThan(loaded, threshold)
                accumulator = HighwayUInt32.minimum(
                    accumulator,
                    HighwayUInt32.selecting(isBelow, identity, loaded)
                )
            }
            return HighwayUInt32.smallest(accumulator)
        } ?? .max
    }
    #endif

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Bias adaptation function](https://datatracker.ietf.org/doc/html/rfc3492#section-6.1)
    @inlinable
    static func adapt(delta: UInt32, codePointCount: UInt32, isFirstTime: Bool) -> UInt32 {
        var delta =
            if isFirstTime {
                delta / Constants.damp
            } else {
                delta / 2
            }
        delta = delta &+ (delta / codePointCount)
        var k: UInt32 = 0
        while delta > (((Constants.base &- Constants.tMin) &* Constants.tMax) / 2) {
            delta = delta / (Constants.base &- Constants.tMin)
            k = k &+ Constants.base
        }
        return k &+ (((Constants.base &- Constants.tMin &+ 1) &* delta) / (delta &+ Constants.skew))
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Parameter values for Punycode](https://datatracker.ietf.org/doc/html/rfc3492#section-5)
    /// 0-25 -> a-z; 26-35 -> 0-9
    /// This function assumes the digit is valid and is in range 0...35.
    @inlinable
    static func uncheckedMapDigitToUTF8Byte(_ digit: UInt32) -> UInt8 {
        assert(digit >= 0 && digit <= 35, "Invalid digit: \(digit)")
        if digit <= 25 {
            return UInt8(truncatingIfNeeded: 0x61 &+ digit)
        }
        /// Assume digit <= 35
        return UInt8(truncatingIfNeeded: 0x30 &+ digit &- 26)
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Parameter values for Punycode](https://datatracker.ietf.org/doc/html/rfc3492#section-5)
    /// A-Z -> 0-25; a-z -> 0-25; 0-9 -> 26-35
    @inlinable
    static func mapCodePointToDigit(_ byte: UInt8) -> UInt8? {
        let value = byte

        /// An uppercase ASCII letter should not make it through to Punycode conversion.
        assert(!(value >= 0x41 && value <= 0x5a))

        if value >= 0x61, value <= 0x7a {
            return value &- 0x61
        }

        if value <= 0x39, value >= 0x30 {
            return value &- 0x30 &+ 26
        }

        return nil
    }
}
