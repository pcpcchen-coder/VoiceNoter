import Foundation
@testable import VoiceNote

/// Records what was delivered and whether paste-at-cursor was requested.
final class MockDeliverer: TranscriptDelivering {
    private(set) var deliveredText: String?
    private(set) var deliveredWithPaste: Bool?
    private(set) var deliverCallCount = 0

    func deliver(_ text: String, pasteAtCursor: Bool) {
        deliveredText = text
        deliveredWithPaste = pasteAtCursor
        deliverCallCount += 1
    }
}
