import Foundation
@testable import VoiceNote

/// 記憶體版憑證儲存，供遷移與 view model 測試使用（不碰真實 Keychain）。
final class InMemoryCredentialStore: CredentialStoring {
    private var stored: String?

    var apiKey: String? { stored }

    func set(_ apiKey: String?) throws {
        stored = (apiKey?.isEmpty == false) ? apiKey : nil
    }

    func clear() throws {
        stored = nil
    }
}
