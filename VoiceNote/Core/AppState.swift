import Foundation
import SwiftUI

enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case error(String)
    case downloadingModel(progress: Double)

    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .downloadingModel:
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
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedModel") ?? "large-v3-turbo"

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

    func refreshMicPermission() {
        self.micPermission = PermissionHelper.microphoneStatus()
    }
}
