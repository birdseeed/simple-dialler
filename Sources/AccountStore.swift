import Foundation
import Security

struct AccountSettings {
    var server: String
    var username: String
    var keychainAccount: String { server.lowercased() + "|" + username }

    static func load() -> AccountSettings {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didImportZoiper") {
            defaults.set(true, forKey: "didImportZoiper")
            if let imported = ZoiperImport.read() {
                defaults.set(imported.server, forKey: "sipServer")
                defaults.set(imported.username, forKey: "sipUsername")
            }
        }
        return AccountSettings(server: defaults.string(forKey: "sipServer") ?? "sip.voipfone.net",
                               username: defaults.string(forKey: "sipUsername") ?? "")
    }

    func save() {
        UserDefaults.standard.set(server, forKey: "sipServer")
        UserDefaults.standard.set(username, forKey: "sipUsername")
    }
}

enum PasswordStore {
    static let service = "com.andybridson.simple-dialler.sip"

    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> (String?, OSStatus) {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else { return (nil, status) }
        return (password, status)
    }

    static func save(_ password: String, account: String) -> OSStatus {
        let request = query(account)
        let data = Data(password.utf8)
        let status = SecItemUpdate(request as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status }
        var insert = request
        insert[kSecValueData as String] = data
        insert[kSecAttrLabel as String] = "Simple Dialler SIP password"
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil)
    }
}

// Read only the supported, non-secret settings. Zoiper's encrypted password is ignored.
private final class ZoiperImport: NSObject, XMLParserDelegate {
    var account: [String: String]?
    var current: String?
    var text = ""
    var result: AccountSettings?
    let fields: Set<String> = ["SIP_domain", "username", "SIP_transport_type",
                               "SIP_use_outbound_proxy", "SIP_use_auth_username"]

    static func read() -> AccountSettings? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Zoiper5/Config.xml")
        guard let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        let importer = ZoiperImport()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = importer
        guard parser.parse() else { return nil }
        return importer.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if name == "account" { account = [:] }
        current = account != nil && fields.contains(name) ? name : nil
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if current == name { account?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name == "account", let values = account {
            if result == nil,
               values["SIP_transport_type"]?.lowercased() == "udp",
               values["SIP_use_outbound_proxy"]?.lowercased() == "false",
               values["SIP_use_auth_username"]?.lowercased() == "false",
               let server = values["SIP_domain"], let username = values["username"],
               DialRules.validServer(server), DialRules.validUsername(username) {
                result = AccountSettings(server: server, username: username)
            }
            account = nil
        }
        current = nil
        text = ""
    }
}
