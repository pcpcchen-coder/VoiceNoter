import Foundation
import os

enum Log {
    static let subsystem = "com.george.voicenote"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let note = Logger(subsystem: subsystem, category: "note")
    static let permission = Logger(subsystem: subsystem, category: "permission")
}
