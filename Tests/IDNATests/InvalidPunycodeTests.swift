import SwiftIDNA
import Testing

@Suite
struct InvalidPunycodeTests {
    /// [UTS #46: Processing, step 4.2](https://www.unicode.org/reports/tr46/#ProcessingStepPunycode)
    /// tells us to leave a label that fails Punycode conversion as it is and carry on with the
    /// next label, so a failing label must not disturb the labels that came before it.
    @available(SwiftStdlib 5.1, *)
    @Test(
        arguments: [
            ("abc.xn--\u{00E9}", "abc.xn--\u{00E9}"),
            ("abc.xn--a-*b", "abc.xn--a-*b"),
            ("abc.xn--0.def", "abc.xn--0.def"),
            ("keep.xn--\u{00E9}.tail", "keep.xn--\u{00E9}.tail"),
            ("xn--maana-pta.xn--\u{00E9}", "ma\u{00F1}ana.xn--\u{00E9}"),
        ]
    )
    func keepsEarlierLabelsWhenALaterLabelFailsToDecode(
        domainName: String,
        expected: String
    ) throws {
        let idna = IDNA(configuration: .mostLax)
        #expect(try idna.toUnicode(domainName: domainName) == expected)
    }
}
