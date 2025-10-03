/// [Punycode: A Bootstring encoding of Unicode for Internationalized Domain Names in Applications (IDNA)](https://datatracker.ietf.org/doc/html/rfc3492)
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
    static func encode(_ input: inout Substring) -> Bool {
        var n = Constants.initialN
        var delta = 0
        var bias = Constants.initialBias
        var output: [Unicode.Scalar] = []
        /// ``input.count <= output.count`` is guaranteed, so we reserve the capacity.
        output.reserveCapacity(input.count)
        output.append(contentsOf: input.unicodeScalars.filter(\.isASCII))
        let b = output.count
        var h = b
        if !output.isEmpty {
            output.append(Unicode.Scalar.asciiHyphenMinus)
        }

        if input.unicodeScalars.contains(where: { !$0.isASCII && $0.value < n }) {
            return false
        }

        while h < input.unicodeScalars.count {
            let m = Int(
                input.unicodeScalars.lazy.filter {
                    !$0.isASCII && $0.value >= n
                }.min().unsafelyUnwrapped.value
            )

            delta &+= ((m &- n) &* (h &+ 1))

            n = m
            for codePoint in input.unicodeScalars {
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
                        output.append(Punycode.uncheckedMapDigitToUnicodeScalar(digit))
                        q = (q &- t) / (Constants.base &- t)
                    }
                    /// Logically this is safe because we know that digit is in the range 0...35
                    /// There are also extensive tests for this in the IDNATests.swift.
                    output.append(Punycode.uncheckedMapDigitToUnicodeScalar(q))

                    bias = adapt(delta: delta, codePointCount: h &+ 1, isFirstTime: h == b)
                    delta = 0
                    h &+= 1
                }
            }
            delta &+= 1
            n &+= 1
        }

        input = Substring(Substring.UnicodeScalarView(output))

        return true
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
    static func decode(_ input: inout Substring) -> Bool {
        var n = Constants.initialN
        var i = 0
        var bias = Constants.initialBias
        var output: [Unicode.Scalar] = []
        output.reserveCapacity(max(input.count, 4))

        if let idx = input.unicodeScalars.lastIndex(of: Unicode.Scalar.asciiHyphenMinus) {
            let afterDelimiterIdx = input.index(after: idx)
            output = Array(input.unicodeScalars[..<idx])
            guard output.allSatisfy(\.isASCII) else {
                return false
            }
            input = Substring(
                Substring.UnicodeScalarView(
                    input.unicodeScalars[afterDelimiterIdx...]
                )
            )
        } else {
            output = []
        }

        while !input.unicodeScalars.isEmpty {
            let oldi = i
            var w = 1
            for k in stride(from: Constants.base, to: .max, by: Constants.base) {
                /// Above we check that input is not empty, so this is safe.
                /// There are also extensive tests for this in the IDNATests.swift.
                guard let codePoint = input.unicodeScalars.first else {
                    return false
                }
                input = Substring(input.unicodeScalars.dropFirst())
                guard let digit = Punycode.mapUnicodeScalarToDigit(codePoint) else {
                    return false
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
            let outputCountPlusOne = output.count &+ 1
            bias = adapt(
                delta: i &- oldi,
                codePointCount: outputCountPlusOne,
                isFirstTime: oldi == 0
            )
            n = n &+ (i / outputCountPlusOne)
            i = i % outputCountPlusOne
            /// Check if n is basic (aka ASCII).
            if n < 128 {
                return false
            }

            output.insert(Unicode.Scalar(n).unsafelyUnwrapped, at: i)

            i &+= 1
        }

        input = Substring(Substring.UnicodeScalarView(output))

        return true
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
    static func uncheckedMapDigitToUnicodeScalar(_ digit: Int) -> Unicode.Scalar {
        assert(digit >= 0 && digit <= 35, "Invalid digit: \(digit)")
        if digit <= 25 {
            return Unicode.Scalar(0x61 &+ digit).unsafelyUnwrapped
        }
        if digit <= 35 {
            return Unicode.Scalar(0x30 &+ digit &- 26).unsafelyUnwrapped
        }
        preconditionFailure("Invalid digit: \(digit)")
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
