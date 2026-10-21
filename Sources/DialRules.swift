import Foundation

enum DialRules {
    static func normalise(_ input: String) -> String? {
        guard input.utf8.count <= 512 else { return nil }
        var result = ""
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 48...57, 42, 35: result.unicodeScalars.append(scalar)
            case 43:
                guard result.isEmpty else { return nil }
                result.append("+")
            case 32, 40, 41, 45, 46, 0xA0, 0x2009, 0x202F: continue
            default: return nil
            }
        }
        guard !result.isEmpty, result != "+", result.count <= 64 else { return nil }
        return result
    }

    static func validUsername(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.+-*").contains($0)
        }
    }

    static func validServer(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty else { return false }
        if parts.count == 2 {
            guard !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                  let port = Int(parts[1]), (1...65535).contains(port) else { return false }
        }
        let labels = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    static func validPassword(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }
}
