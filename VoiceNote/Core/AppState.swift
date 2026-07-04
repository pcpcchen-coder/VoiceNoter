import Foundation
import SwiftUI

enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case error(String)
    case downloadingModel(progress: Double)
    case loadingModel

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .downloadingModel, .loadingModel:
            return true
        case .idle, .error:
            return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 設定持久化來源。所有 `setXxx` 都會先寫入這裡再更新對應的 `@Published`。
    /// 對外可讀，供 coordinator 組 `DecodingSettings` 與存取模型路徑快取（Step 10 改為顯式注入）。
    let settings: SettingsStore

    @Published var state: RecorderState = .idle
    @Published var lastTranscript: String = ""
    /// 錯誤訊息（選單顯示為紅字）。只用於失敗。
    @Published var lastError: String? = nil
    /// 資訊／成功訊息（選單顯示為灰字）。與 `lastError` 分流，避免成功訊息被當成錯誤。
    @Published var infoMessage: String? = nil
    @Published var micPermission: MicrophonePermissionStatus = .undetermined
    @Published var selectedModel: String
    @Published var autoProofread: Bool
    @Published var chineseVariant: ChineseVariant
    @Published var pasteAtCursor: Bool
    @Published var decodingTopK: Int
    @Published var decodingTemperature: Float
    @Published var decodingFallbackCount: Int

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.selectedModel = settings.selectedModel
        self.autoProofread = settings.autoProofread
        self.chineseVariant = settings.chineseVariant
        self.pasteAtCursor = settings.pasteAtCursor
        self.decodingTopK = settings.decodingTopK
        self.decodingTemperature = settings.decodingTemperature
        self.decodingFallbackCount = settings.decodingFallbackCount
        self.micPermission = PermissionHelper.microphoneStatus()
    }

    /// Hard error — sets state to `.error`. Use for failures that block normal operation
    /// (e.g. model load failure). The status icon will reflect this.
    func setError(_ message: String) {
        Log.app.error("AppState error: \(message, privacy: .public)")
        self.lastError = message
        self.state = .error(message)
    }

    /// Soft failure — keeps state at `.idle` but surfaces a red message in the menu.
    /// Use for transient errors like a single transcription failure.
    func noteSoftFailure(_ message: String) {
        Log.app.error("AppState soft failure: \(message, privacy: .public)")
        self.lastError = message
        self.state = .idle
    }

    /// Info / success message — shown gray in the menu. Never routed through `lastError`.
    func noteInfo(_ message: String) {
        Log.app.info("AppState info: \(message, privacy: .public)")
        self.infoMessage = message
    }

    /// Surfaces a red message without changing the recorder state (e.g. "please wait"
    /// while a model is still loading — we must not clobber `.downloadingModel`).
    func flashError(_ message: String) {
        self.lastError = message
    }

    /// Clears both transient messages (error + info). Called when a new recording starts.
    func clearTransientError() {
        self.lastError = nil
        self.infoMessage = nil
        if case .error = self.state {
            self.state = .idle
        }
    }

    func updateModelChoice(_ name: String) {
        settings.selectedModel = name
        self.selectedModel = name
    }

    func setAutoProofread(_ enabled: Bool) {
        settings.autoProofread = enabled
        self.autoProofread = enabled
    }

    func setChineseVariant(_ variant: ChineseVariant) {
        settings.chineseVariant = variant
        self.chineseVariant = variant
    }

    func setPasteAtCursor(_ enabled: Bool) {
        settings.pasteAtCursor = enabled
        self.pasteAtCursor = enabled
    }

    func setDecodingTopK(_ value: Int) {
        settings.decodingTopK = value
        self.decodingTopK = value
    }

    func setDecodingTemperature(_ value: Float) {
        settings.decodingTemperature = value
        self.decodingTemperature = value
    }

    func setDecodingFallbackCount(_ value: Int) {
        settings.decodingFallbackCount = value
        self.decodingFallbackCount = value
    }

    func refreshMicPermission() {
        self.micPermission = PermissionHelper.microphoneStatus()
    }
}
