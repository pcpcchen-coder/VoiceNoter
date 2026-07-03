import Foundation
@testable import VoiceNote

/// Records call counts and lets tests inject start errors or the stop() result.
final class MockAudioRecorder: AudioRecording {
    var startError: Error?
    private(set) var startCallCount = 0

    var stopResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/voicenote-mock.wav"))
    private(set) var stopCallCount = 0

    func start() throws {
        startCallCount += 1
        if let startError { throw startError }
    }

    func stop() async throws -> URL {
        stopCallCount += 1
        switch stopResult {
        case .success(let url): return url
        case .failure(let error): throw error
        }
    }
}
