import Foundation

struct RecentCall: Codable, Equatable {
    let number: String
    let date: Date
    let outcome: String // outgoing, missed, rejected, answered
    var unread: Bool
}

struct CallHistory {
    private(set) var entries: [RecentCall] = []
    let defaults: UserDefaults
    let key: String

    init(account: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "recentCalls.v1." + Data(account.utf8).base64EncodedString()
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([RecentCall].self, from: data) {
            entries = saved.filter { $0.number.utf8.count <= 256 && ["outgoing", "missed", "rejected", "answered"].contains($0.outcome) }
            trim()
        }
    }

    var missedCount: Int { entries.filter { $0.outcome == "missed" && $0.unread }.count }

    mutating func record(_ number: String, outcome: String, date: Date = Date()) {
        guard !number.isEmpty else { return }
        if outcome == "outgoing" { entries.removeAll { $0.outcome == "outgoing" && $0.number == number } }
        entries.insert(RecentCall(number: number, date: date, outcome: outcome, unread: outcome == "missed"), at: 0)
        trim()
        save()
    }

    private mutating func trim() {
        var outgoing = 0, incoming = 0
        entries = entries.filter {
            if $0.outcome == "outgoing" { outgoing += 1; return outgoing <= 20 }
            incoming += 1; return incoming <= 20
        }
    }
    mutating func markSeen() {
        for i in entries.indices { entries[i].unread = false }
        save()
    }
    mutating func clear() { entries = []; defaults.removeObject(forKey: key) }
    private func save() { if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) } }
}

enum CallPresentation {
    static func callbackNumber(_ remote: String) -> String? {
        if let direct = DialRules.normalise(remote) { return direct }
        guard let start = remote.range(of: "sip:", options: .caseInsensitive),
              let end = remote[start.upperBound...].firstIndex(of: "@") else { return nil }
        return DialRules.normalise(String(remote[start.upperBound..<end]).replacingOccurrences(of: "%23", with: "#"))
    }
    static func duration(_ seconds: UInt64) -> String {
        String(format: "%02llu:%02llu", seconds / 60, seconds % 60)
    }
    static func failure(_ code: Int32) -> String {
        switch code {
        case 401, 403, 407: return "Account not authorised. Check your SIP details in Settings."
        case 404, 484: return "Number or account not found. Check the number and SIP account."
        case 408, 504: return "No response. Check your network, then reconnect."
        case 480: return "The person you called is unavailable."
        case 486, 600: return "The person you called is busy."
        case 487: return "Call cancelled."
        case 488, 415: return "The provider could not agree an audio format."
        case 500...599: return "The telephone service is unavailable. Try again later."
        case 603: return "The call was declined."
        default: return "The operation failed. Check your connection and audio devices."
        }
    }
}

// Coalesce wake/path notifications and defer recovery until the single call ends.
struct RecoveryPolicy {
    var pending = false
    var notBefore: TimeInterval = 0
    var lastAttempt: TimeInterval = -.infinity
    mutating func request(now: TimeInterval) { pending = true; notBefore = now + 2 }
    mutating func shouldRefresh(now: TimeInterval, online: Bool, idle: Bool) -> Bool {
        guard pending, online, idle, now >= notBefore, now - lastAttempt >= 5 else { return false }
        pending = false; lastAttempt = now
        return true
    }
}
