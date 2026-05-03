import Foundation

/// 負責將整份筆記送去 AI 服務（預設 OpenAI ChatGPT），回傳重寫/摘要的內容。
struct AIRewriter {
    enum Provider {
        case openAI
        // 預留: case claude
    }

    /// 用於未來切換不同 AI 供應商
    static var provider: Provider = .openAI

    /// 送出筆記並等待 AI 整理後回覆
    /// - Parameters:
    ///   - text: 要整理的原始內容
    ///   - completion: 取得結果 callback
    static func rewrite(_ text: String) async throws -> String {
        switch provider {
        case .openAI:
            return try await rewriteWithOpenAI(text)
        }
    }

    /// 實作 OpenAI GPT-3.5/4 API 呼叫
    private static func rewriteWithOpenAI(_ text: String) async throws -> String {
        guard let apiKey = await OpenAIOAuthManager.shared.accessToken, !apiKey.isEmpty else {
            throw NSError(domain: "AIRewriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "尚未設定 OpenAI API Key，請至設定頁面輸入。"])
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let messages = [
            ["role": "system", "content": "你是一位善於整理中文筆記的助手，請將用戶給的內容邏輯梳理、轉為更有條理的條列式摘要，並以繁體中文回覆。"],
            ["role": "user", "content": text],
        ]
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.5
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorInfo = errorDict["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                throw NSError(domain: "AIRewriter", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI API 錯誤（\(httpResponse.statusCode)）：\(message)"])
            }
            throw NSError(domain: "AIRewriter", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI API 錯誤（\(httpResponse.statusCode)）：\(detail)"])
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AIRewriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "解析 AI 回應失敗"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
