import Foundation
import Security

/// 可讀寫的憑證儲存介面（擴充 `CredentialProviding`）。
protocol CredentialStoring: CredentialProviding, AnyObject {
    func set(_ apiKey: String?) throws
    func clear() throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain 操作失敗（\(status)）"
        }
    }
}

/// 以 macOS Keychain（generic password）保存 OpenAI API Key。
/// 無狀態：多個實例讀寫的是同一個 Keychain 項目。
final class KeychainCredentialStore: CredentialStoring {
    private let service: String
    private let account: String

    init(service: String = "com.george.voicenote", account: String = "openai_api_key") {
        self.service = service
        self.account = account
    }

    var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else {
            return nil
        }
        return string
    }

    func set(_ apiKey: String?) throws {
        guard let apiKey, !apiKey.isEmpty else {
            try clear()
            return
        }
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// 一次性把舊版存在 `UserDefaults` 的明文 token 遷移到憑證儲存，並清掉舊 key。
/// 已有 Keychain 值時不覆蓋。App 啟動時呼叫。
@discardableResult
func migrateLegacyToken(defaults: UserDefaults, into store: CredentialStoring) -> Bool {
    let accessKey = "openai_access_token"
    let refreshKey = "openai_refresh_token"
    defer {
        defaults.removeObject(forKey: accessKey)
        defaults.removeObject(forKey: refreshKey)
    }

    // 已有憑證就不覆蓋，只清掉殘留的舊 defaults token。
    if store.apiKey?.isEmpty == false { return false }

    guard let token = defaults.string(forKey: accessKey), !token.isEmpty else {
        return false
    }
    try? store.set(token)
    return true
}
