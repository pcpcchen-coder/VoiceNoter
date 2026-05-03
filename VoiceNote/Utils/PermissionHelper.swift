import Foundation
import AVFoundation
import AppKit
import ApplicationServices

enum MicrophonePermissionStatus {
    case authorized
    case denied
    case undetermined
}

enum PermissionHelper {
    static func microphoneStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    /// Triggers the system permission prompt the first time. Returns true on grant.
    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func openMicrophoneSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
