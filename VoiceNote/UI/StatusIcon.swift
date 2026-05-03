import SwiftUI

struct StatusIcon: View {
    let state: RecorderState
    let micDenied: Bool

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .help(tooltip)
    }

    private var symbolName: String {
        if micDenied { return "mic.slash" }
        switch state {
        case .idle, .error: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .downloadingModel: return "arrow.down.circle"
        case .loadingModel: return "cpu"
        }
    }

    private var tint: Color {
        if micDenied { return .secondary }
        switch state {
        case .recording: return .red
        case .error: return .secondary
        default: return .primary
        }
    }

    private var tooltip: String {
        if micDenied { return "VoiceNote — 麥克風權限未授予" }
        switch state {
        case .idle: return "VoiceNote — 待機中"
        case .recording: return "VoiceNote — 錄音中"
        case .transcribing: return "VoiceNote — 轉錄中"
        case .error(let m): return "VoiceNote — 錯誤：\(m)"
        case .downloadingModel(let p):
            return "VoiceNote — 下載模型中 \(Int(p * 100))%"
        case .loadingModel:
            return "VoiceNote — 載入模型中（首次可能需要數分鐘）"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusIcon(state: .idle, micDenied: false)
        StatusIcon(state: .recording(startedAt: Date()), micDenied: false)
        StatusIcon(state: .transcribing, micDenied: false)
        StatusIcon(state: .downloadingModel(progress: 0.5), micDenied: false)
        StatusIcon(state: .idle, micDenied: true)
    }
    .padding()
}
