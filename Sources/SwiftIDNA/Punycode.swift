/// [Punycode: A Bootstring encoding of Unicode for Internationalized Domain Names in Applications (IDNA)](https://datatracker.ietf.org/doc/html/rfc3492)
@available(swiftIDNAApplePlatforms 13, *)
enum Punycode {
    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Parameter values for Punycode](https://datatracker.ietf.org/doc/html/rfc3492#section-5)
    enum Constants {
        @usableFromInline
        static var base: Int {
            36
        }

        @usableFromInline
        static var tMin: Int {
            1
        }

        @usableFromInline
        static var tMax: Int {
            26
        }

        @usableFromInline
        static var skew: Int {
            38
        }

        @usableFromInline
        static var damp: Int {
            700
        }

        @usableFromInline
        static var initialBias: Int {
            72
        }

        @usableFromInline
        static var initialN: Int {
            128
        }
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Encoding procedure](https://datatracker.ietf.org/doc/html/rfc3492#section-6.3)
    /// Returns true if successful and false if conversion failed.
    ///
    /// This function uses unchecked/unsafe handling of some values. These are all safe.
    /// This function is heavily tested with 12_000+ tests from Unicode's IDNA V2 test suite.
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
    @inlinable
    static func encode(uncheckedUTF8Span inputBytesSpan: Span<UInt8>) -> [UInt8] {
        var n = Constants.initialN
        var delta = 0
        var bias = Constants.initialBias
        var output: [UInt8] = []
        /// ``input.count <= output.count`` is guaranteed when using unicode scalars.
        /// We're using utf8 bytes but we'll reserve the capacity anyway.
        output.reserveCapacity(inputBytesSpan.count)
        for idx in inputBytesSpan.indices {
            let byte = inputBytesSpan[unchecked: idx]
            if byte.isASCII {
                output.append(byte)
            }
        }
        let b = output.count
        var h = b

        var unicodeScalarsIterator = inputBytesSpan.makeUnicodeScalarIteratorCompatibility()
        /// Mark h-amount of Unicode Scalars, as already-read.
        for _ in 0..<h {
            _ = unicodeScalarsIterator.skipForward()
        }

        if !output.isEmpty {
            output.append(UInt8.asciiHyphenMinus)
        }

        /// FIXME: check to see if Int is enough in 32-bit platforms too

        /// FIXME: it's probably more efficient to collect all unicode scalars, considering the
        /// calculations needed for `m`

        while unicodeScalarsIterator.currentCodeUnitOffset != inputBytesSpan.count {
            var m: Int = .max
            var unicodeScalarsIteratorForM = inputBytesSpan.makeUnicodeScalarIteratorCompatibility()
            while let codePoint = unicodeScalarsIteratorForM.next() {
                if !codePoint.isASCII, codePoint.value >= n {
                    m = min(m, Int(codePoint.value))
                }
            }

            delta &+= ((m &- n) &* (h &+ 1))

            n = m
            var originalUnicodeScalarsIterator =
                inputBytesSpan.makeUnicodeScalarIteratorCompatibility()
            while let codePoint = originalUnicodeScalarsIterator.next() {
                if codePoint.value < n || codePoint.isASCII {
                    delta &+= 1
                }

                if codePoint.value == n {
                    var q = delta
                    for k in stride(from: Constants.base, to: .max, by: Constants.base) {
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
                    _ = unicodeScalarsIterator.skipForward()
                }
            }
            delta &+= 1
            n &+= 1
        }

        return output
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Decoding procedure](https://datatracker.ietf.org/doc/html/rfc3492#section-6.2)
    /// Returns true if successful and false if conversion failed.
    ///
    /// This function uses unchecked/unsafe handling of some values. These are all safe.
    /// This function is heavily tested with 12_000+ tests from Unicode's IDNA V2 test suite.
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
    @inlinable
    static func decode(uncheckedUTF8Span inputBytesSpan: Span<UInt8>) -> [UInt8]? {
        var inputBytesSpan = inputBytesSpan
        var n = Constants.initialN
        var i = 0
        var bias = Constants.initialBias
        var output: [UInt8] = []
        output.reserveCapacity(max(inputBytesSpan.count, 4))

        if let utf8Idx = inputBytesSpan.lastIndex(of: .asciiHyphenMinus) {
            let afterDelimiterIdx = utf8Idx &+ 1
            let range = Range<Int>(uncheckedBounds: (0, utf8Idx))
            let bytesSpanChunk = inputBytesSpan.extracting(unchecked: range)
            output.append(span: bytesSpanChunk)

            guard output.allSatisfy(\.isASCII) else {
                return nil
            }

            let inputBytesRange = Range<Int>(
                uncheckedBounds: (afterDelimiterIdx, inputBytesSpan.count)
            )
            inputBytesSpan = inputBytesSpan.extracting(unchecked: inputBytesRange)
        }

        var unicodeScalarsIterator = inputBytesSpan.makeUnicodeScalarIteratorCompatibility()

        /// unicodeScalarsIndexToUtf8Index[unicodeScalarsIndex] = utf8Index
        /// TODO: check if this "lookup table" is actually needed or not.
        var unicodeScalarsIndexToUTF8Index = (0..<output.count).map { $0 }
        while unicodeScalarsIterator.currentCodeUnitOffset != inputBytesSpan.count {
            let oldi = i
            var w = 1
            for k in stride(from: Constants.base, to: .max, by: Constants.base) {
                /// Above we check that input is not empty, so this is safe.
                /// There are also extensive tests for this in the IDNATests.swift.
                guard let codePoint = unicodeScalarsIterator.next() else {
                    return nil
                }
                guard let digit = Punycode.mapUnicodeScalarToDigit(codePoint) else {
                    return nil
                }

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
                    break
                }

                w = w &* (Constants.base &- t)
            }
            let outputCount = unicodeScalarsIndexToUTF8Index.count
            let outputCountPlusOne = outputCount &+ 1
            bias = adapt(
                delta: i &- oldi,
                codePointCount: outputCountPlusOne,
                isFirstTime: oldi == 0
            )
            n = n &+ (i / outputCountPlusOne)
            i = i % outputCountPlusOne
            /// Check if n is basic (aka ASCII).
            if n.isASCII {
                return nil
            }

            let scalar = Unicode.Scalar(n).unsafelyUnwrapped

            if i == unicodeScalarsIndexToUTF8Index.count {
                output.append(contentsOf: scalar.utf8)
                unicodeScalarsIndexToUTF8Index.append(output.count &- 1)
            } else {
                let previousIdxOfScalarInBytes =
                    i == 0
                    ? 0
                    : unicodeScalarsIndexToUTF8Index[i &- 1]
                let insertIndex =
                    i == 0
                    ? 0
                    : previousIdxOfScalarInBytes &+ 1
                output.insert(contentsOf: scalar.utf8, at: insertIndex)
                let utf8Count = scalar.utf8.count
                let firstElementFactor = i == 0 ? -1 : 0
                unicodeScalarsIndexToUTF8Index.insert(
                    previousIdxOfScalarInBytes &+ utf8Count &+ firstElementFactor,
                    at: i
                )
                let currentCount = unicodeScalarsIndexToUTF8Index.count
                for idx in (i &+ 1)..<currentCount {
                    unicodeScalarsIndexToUTF8Index[idx] &+= utf8Count
                }
            }

            i &+= 1
        }

        return output
    }

    /// [Punycode: A Bootstring encoding of Unicode for IDNA: Bias adaptation function](https://datatracker.ietf.org/doc/html/rfc3492#section-6.1)
    @inlinable
    static func adapt(delta: Int, codePointCount: Int, isFirstTime: Bool) -> Int {
        var delta =
            if isFirstTime {
                delta / Constants.damp
            } else {
                delta / 2
            }
        delta = delta &+ (delta / codePointCount)
        var k = 0
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
    static func uncheckedMapDigitToUTF8Byte(_ digit: Int) -> UInt8 {
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
    static func mapUnicodeScalarToDigit(_ unicodeScalar: Unicode.Scalar) -> Int? {
        let value = unicodeScalar.value

        if value >= 0x61, value <= 0x7a {
            return Int(value &- 0x61)
        }

        if value >= 0x41, value <= 0x5a {
            return Int(value &- 0x41)
        }

        if value <= 0x39, value >= 0x30 {
            return Int(value &- 0x30 &+ 26)
        }

        return nil
    }
}
