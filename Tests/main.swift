import Foundation

var count = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("FAIL: \(description)") }
    count += 1
}

expect(DialRules.normalise("+44 (0) 1624-123-456") == "+4401624123456", "Preserves exactly the supplied digits")
expect(DialRules.normalise(" 01624 123456 ") == "01624123456", "Space removal")
expect(DialRules.normalise("*21*+44#") == nil, "Plus cannot be embedded in a service code")
expect(DialRules.normalise("*21*123456#") == "*21*123456#", "Service codes")
expect(DialRules.normalise("+44\u{A0}1624\u{202F}123456") == "+441624123456", "Formatted clipboard spaces")
expect(DialRules.normalise("+") == nil, "Reject bare plus")
expect(DialRules.normalise("- ()") == nil, "Reject empty formatted input")
expect(DialRules.normalise("++441624") == nil, "Reject duplicate plus")
for value in ["sip:123@evil.test", "123;transport=tcp", "123?x=1", "123\r\nX-Test: injected", "123\n", "123\t456", "123\u{0}456", "CALLNOW", "١٢٣", "１２３"] {
    expect(DialRules.normalise(value) == nil, "Reject URI, controls and unrequested characters")
}
expect(DialRules.normalise(String(repeating: "1", count: 65)) == nil, "Bound dial length")
expect(DialRules.validUsername("12345678*202"), "Voipfone account plus extension")
expect(!DialRules.validUsername("user@elsewhere"), "Username cannot replace host")
expect(!DialRules.validUsername("user\r\n"), "Username header injection")
expect(DialRules.validServer("sip.voipfone.net"), "Hostname")
expect(DialRules.validServer("sip.example.test:5060"), "Explicit port")
for value in ["sip:evil.test", "example.test@evil.test", "example.test;transport=tcp", "example..test", "example.test:0", "example.test:65536", "example.test:", "-bad.test", "bad-.test", "example.test\n"] {
    expect(!DialRules.validServer(value), "Reject invalid server")
}
expect(DialRules.validPassword("dummy-test-password"), "Password allowed")
expect(!DialRules.validPassword("secret\n"), "Password control validation")
print("Passed \(count) dial and account validation checks.")
