import Foundation
@testable import VoiceNote

/// 可設定回傳/拋錯並記錄輸入的 `TextRewriting` mock。供 Step 10/11 的流程測試使用。
final class MockRewriter: TextRewriting {
    var result: Result<String, Error> = .success("rewritten")
    private(set) var calls: [String] = []

    func rewrite(_ text: String) async throws -> String {
        calls.append(text)
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
