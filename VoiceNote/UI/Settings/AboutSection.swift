import SwiftUI

struct AboutSection: View {
    var body: some View {
        Section("關於") {
            LabeledContent("版本") {
                Text(Self.versionString)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
