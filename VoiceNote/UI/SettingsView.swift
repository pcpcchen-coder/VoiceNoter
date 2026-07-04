import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var credentials = CredentialsViewModel()
    @StateObject private var modelDownload = ModelDownloadViewModel(settings: SettingsStore())

    var body: some View {
        Form {
            HotkeySection()
            ModelSection(state: state, download: modelDownload)
            DecodingSection(state: state)
            OutputSection(state: state)
            ProofreadSection(state: state, credentials: credentials)
            NotesSection()
            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 880)
        .padding()
    }
}

#Preview {
    SettingsView().environmentObject(AppState.shared)
}
