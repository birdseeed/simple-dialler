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

let suite = "com.andybridson.simple-dialler.tests.\(UUID().uuidString)"
let testDefaults = UserDefaults(suiteName: suite)!
var history = CallHistory(account: "example.test|alice", defaults: testDefaults)
for i in 0..<25 { history.record(String(i), outcome: "outgoing") }
expect(history.entries.count == 20 && history.entries.first?.number == "24", "Last twenty outgoing, newest first")
history.record("10", outcome: "outgoing")
expect(history.entries.count == 20 && history.entries.first?.number == "10", "Redial deduplicates and moves to front")
expect(history.entries.filter { $0.number == "10" }.count == 1, "Redial appears once")
history.record("sip:123@example.test", outcome: "missed")
history.record("sip:456@example.test", outcome: "rejected")
expect(history.missedCount == 1, "Rejected call does not count as missed")
expect(history.entries.filter { $0.outcome == "outgoing" }.count == 20, "Incoming calls retain outgoing twenty")
let loaded = CallHistory(account: "example.test|alice", defaults: testDefaults)
expect(loaded.entries == history.entries, "History survives relaunch")
var other = CallHistory(account: "example.test|bob", defaults: testDefaults)
expect(other.entries.isEmpty, "Account histories are isolated")
history.markSeen()
expect(history.missedCount == 0 && history.entries.contains { $0.outcome == "missed" }, "Mark seen retains missed history")
other.record("999", outcome: "outgoing")
history.clear()
expect(CallHistory(account: "example.test|alice", defaults: testDefaults).entries.isEmpty, "Clear persists")
expect(CallHistory(account: "example.test|bob", defaults: testDefaults).entries.count == 1, "Clear affects only selected account")
testDefaults.removePersistentDomain(forName: suite)
expect(CallPresentation.callbackNumber("\"Caller\" <sip:+441234@example.test>") == "+441234", "Incoming callback extracts digits only")
expect(CallPresentation.callbackNumber("sip:*123%23@example.test") == "*123#", "Escaped service-code callback")
expect(CallPresentation.callbackNumber("sip:person@example.test") == nil, "Cannot dial arbitrary SIP caller URI")
expect(CallPresentation.duration(0) == "00:00", "Timer starts at zero")
expect(CallPresentation.duration(65) == "01:05", "Timer minute rollover")
expect(CallPresentation.duration(3600) == "60:00", "Timer supports long calls")
expect(CallPresentation.failure(486).contains("busy"), "Busy is readable")
expect(CallPresentation.failure(403).contains("authorised"), "Account rejection is readable")
var recovery = RecoveryPolicy()
recovery.request(now: 10)
expect(!recovery.shouldRefresh(now: 11, online: true, idle: true), "Wake recovery waits for network settling")
expect(!recovery.shouldRefresh(now: 13, online: false, idle: true), "Offline recovery remains pending")
expect(!recovery.shouldRefresh(now: 14, online: true, idle: false), "Recovery never interrupts a call")
expect(recovery.shouldRefresh(now: 15, online: true, idle: true), "Deferred recovery happens after call")
expect(!recovery.shouldRefresh(now: 16, online: true, idle: true), "Recovery does not repeat without another event")
recovery.request(now: 16)
expect(!recovery.shouldRefresh(now: 18, online: true, idle: true), "Recovery rate limit coalesces changes")
expect(recovery.shouldRefresh(now: 20, online: true, idle: true), "Rate-limited recovery eventually runs")
print("Passed \(count) total validation, history, presentation and recovery checks.")
