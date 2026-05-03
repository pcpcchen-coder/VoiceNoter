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

    @Published var state: RecorderState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastError: String? = nil
    @Published var micPermission: MicrophonePermissionStatus = .undetermined
    @Published var selectedModel: String = AppState.migrateModelName(
        UserDefaults.standard.string(forKey: "selectedModel") ?? "openai_whisper-large-v3_turbo"
    )

    private static let modelNameMigration: [String: String] = [
        "tiny": "openai_whisper-small",
        "base": "openai_whisper-small",
        "small": "openai_whisper-small",
        "medium": "openai_whisper-large-v3_turbo_954MB",
        "large-v2": "openai_whisper-large-v3_turbo_954MB",
        "large-v3": "openai_whisper-large-v3",
        "large-v3-turbo": "openai_whisper-large-v3_turbo",
        "openai_whisper-large-v2": "openai_whisper-large-v3_turbo_954MB",
    ]

    private static func migrateModelName(_ name: String) -> String {
        if let mapped = modelNameMigration[name] {
            UserDefaults.standard.set(mapped, forKey: "selectedModel")
            return mapped
        }
        return name
    }
    @Published var autoProofread: Bool = UserDefaults.standard.bool(forKey: "autoProofread")
    @Published var chineseVariant: String = UserDefaults.standard.string(forKey: "chineseVariant") ?? "zh-Hant"
    @Published var pasteAtCursor: Bool = UserDefaults.standard.object(forKey: "pasteAtCursor") as? Bool ?? true
    @Published var decodingTopK: Int = UserDefaults.standard.object(forKey: "decodingTopK") as? Int ?? 5
    @Published var decodingTemperature: Float = UserDefaults.standard.object(forKey: "decodingTemperature") as? Float ?? 0.0
    @Published var decodingFallbackCount: Int = UserDefaults.standard.object(forKey: "decodingFallbackCount") as? Int ?? 5

    private init() {
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

    func clearTransientError() {
        self.lastError = nil
        if case .error = self.state {
            self.state = .idle
        }
    }

    func updateModelChoice(_ name: String) {
        UserDefaults.standard.set(name, forKey: "selectedModel")
        self.selectedModel = name
    }

    func setAutoProofread(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "autoProofread")
        self.autoProofread = enabled
    }

    func setChineseVariant(_ variant: String) {
        UserDefaults.standard.set(variant, forKey: "chineseVariant")
        self.chineseVariant = variant
    }

    func setPasteAtCursor(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "pasteAtCursor")
        self.pasteAtCursor = enabled
    }

    func setDecodingTopK(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "decodingTopK")
        self.decodingTopK = value
    }

    func setDecodingTemperature(_ value: Float) {
        UserDefaults.standard.set(value, forKey: "decodingTemperature")
        self.decodingTemperature = value
    }

    func setDecodingFallbackCount(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "decodingFallbackCount")
        self.decodingFallbackCount = value
    }

    func refreshMicPermission() {
        self.micPermission = PermissionHelper.microphoneStatus()
    }
}
