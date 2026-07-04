import Foundation
@testable import VoiceNote

/// Emits the configured progress values, optionally suspends until released, then
/// returns/throws the configured result. Records call count.
final class MockModelDownloader: ModelDownloading {
    var progressValues: [Double] = []
    var result: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/voicenote-model"))
    private(set) var downloadCallCount = 0

    /// When true, download suspends after emitting progress until `release()` is called.
    var holdUntilReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func download(variant: String, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        downloadCallCount += 1
        for value in progressValues {
            await progress(value)
        }
        if holdUntilReleased {
            await withCheckedContinuation { self.continuation = $0 }
        }
        switch result {
        case .success(let url): return url
        case .failure(let error): throw error
        }
    }
}
