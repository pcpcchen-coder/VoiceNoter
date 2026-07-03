import Foundation

/// 設定頁認證區塊的 view model：包一個 `CredentialStoring`，發布「已認證」狀態。
@MainActor
final class CredentialsViewModel: ObservableObject {
    @Published private(set) var isAuthenticated: Bool

    private let store: CredentialStoring

    init(store: CredentialStoring = KeychainCredentialStore()) {
        self.store = store
        self.isAuthenticated = store.apiKey?.isEmpty == false
    }

    func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.set(trimmed)
        refresh()
    }

    func clear() {
        try? store.clear()
        refresh()
    }

    private func refresh() {
        isAuthenticated = store.apiKey?.isEmpty == false
    }
}
