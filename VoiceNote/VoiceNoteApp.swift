import SwiftUI
import AppKit

@main
struct VoiceNoteApp: App {
    @StateObject private var state: AppState
    @StateObject private var coordinator: RecordingCoordinator

    @MainActor
    init() {
        Paths.ensureDirectoriesExist()
        GlossaryStore().bootstrapIfNeeded()
        migrateLegacyToken(defaults: .standard, into: KeychainCredentialStore())

        let appState = AppState.shared
        let coordinator = RecordingCoordinator(
            state: appState,
            settings: appState.settings,
            recorder: AudioRecorder(),
            transcriber: WhisperKitTranscriber(settings: appState.settings),
            noteStore: FileNoteStore(),
            rewriter: OpenAIRewriter(credentials: KeychainCredentialStore()),
            deliverer: SystemTranscriptDeliverer(),
            glossary: GlossaryStore()
        )
        coordinator.activate()

        _state = StateObject(wrappedValue: appState)
        _coordinator = StateObject(wrappedValue: coordinator)
        PermissionHelper.requestAccessibilityIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(coordinator)
        } label: {
            StatusIcon(state: state.state, micDenied: state.micPermission == .denied)
            // Show the download % right on the menu-bar label so progress is visible
            // at a glance, without opening the menu or hovering for the tooltip.
            if state.micPermission != .denied,
               let percent = MenuStatusText.menuBarProgressText(state: state.state) {
                Text(percent)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("VoiceNote 設定", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
