import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: [.option]))
}

/// Bridges the KeyboardShortcuts package's keyDown/keyUp events to push-to-talk callbacks.
@MainActor
final class HotkeyManager {
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            Log.hotkey.debug("Hotkey down")
            self?.onPress()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            Log.hotkey.debug("Hotkey up")
            self?.onRelease()
        }
    }

    func unregister() {
        KeyboardShortcuts.disable(.pushToTalk)
    }
}
