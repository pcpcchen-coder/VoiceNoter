import Foundation

/// 把一段文字送去 AI 服務整理／校稿的抽象介面。
/// 以 protocol 讓核心流程（Step 10/11）能注入 mock。
protocol TextRewriting {
    func rewrite(_ text: String) async throws -> String
}

/// 提供 API 憑證的抽象介面。Step 8 會由 Keychain-backed 實作取代目前的過渡實作。
protocol CredentialProviding {
    var apiKey: String? { get }
}
