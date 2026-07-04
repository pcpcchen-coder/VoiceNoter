import SwiftUI

struct DecodingSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        Section("解碼參數") {
            Stepper(
                "Top-K：\(state.decodingTopK)",
                value: Binding(get: { state.decodingTopK }, set: { state.setDecodingTopK($0) }),
                in: 1...20
            )
            Text("取機率最高的 K 個 token 做取樣，值越大結果越多樣。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Temperature：\(String(format: "%.1f", state.decodingTemperature))")
                Slider(
                    value: Binding(get: { state.decodingTemperature }, set: { state.setDecodingTemperature($0) }),
                    in: 0.0...1.0,
                    step: 0.1
                )
            }
            Text("取樣溫度，0 = greedy（最穩定），越高越隨機。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(
                "溫度重試次數：\(state.decodingFallbackCount)",
                value: Binding(get: { state.decodingFallbackCount }, set: { state.setDecodingFallbackCount($0) }),
                in: 0...10
            )
            Text("品質不佳時自動升溫重試的次數，效果類似 best_of。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
