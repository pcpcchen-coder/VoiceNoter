import Foundation

enum OpenAIRewriterError: LocalizedError, Equatable {
    case missingAPIKey
    case http(status: Int, message: String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未設定 OpenAI API Key，請至設定頁面輸入。"
        case .http(let status, let message):
            return "OpenAI API 錯誤（\(status)）：\(message)"
        case .decodingFailed:
            return "解析 AI 回應失敗"
        }
    }
}

/// 透過 OpenAI Chat Completions 整理／校稿中文筆記。
///
/// 憑證與 `URLSession` 皆可注入，request/response 走 `Codable`，
/// 讓整體流程能以 `URLProtocol` stub 在不連網的情況下測試。
final class OpenAIRewriter: TextRewriting {
    private let credentials: CredentialProviding
    private let session: URLSession
    private let model: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let systemPrompt =
        "你是一位善於整理中文筆記的助手，請將用戶給的內容邏輯梳理、轉為更有條理的條列式摘要，並以繁體中文回覆。"

    init(
        credentials: CredentialProviding,
        session: URLSession = .shared,
        model: String = "gpt-4o-mini"
    ) {
        self.credentials = credentials
        self.session = session
        self.model = model
    }

    func rewrite(_ text: String) async throws -> String {
        guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
            throw OpenAIRewriterError.missingAPIKey
        }

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: text),
            ],
            maxTokens: 2048,
            temperature: 0.5
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIRewriterError.decodingFailed
        }
        guard http.statusCode == 200 else {
            let serverMessage = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw OpenAIRewriterError.http(status: http.statusCode, message: serverMessage)
        }

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw OpenAIRewriterError.decodingFailed
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Codable payloads

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String }
}

private struct ErrorResponse: Decodable {
    let error: ErrorDetail
    struct ErrorDetail: Decodable { let message: String }
}
