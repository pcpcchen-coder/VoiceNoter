import XCTest
import Combine
@testable import VoiceNote

@MainActor
final class ModelDownloadViewModelTests: XCTestCase {

    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "MDVM-\(UUID().uuidString)")!)
    }

    func test_download_publishesProgressUpdates() async {
        let downloader = MockModelDownloader()
        downloader.progressValues = [0.25, 0.75]
        let vm = ModelDownloadViewModel(downloader: downloader, settings: makeSettings())

        var seen: [Double] = []
        let cancellable = vm.$status.sink { status in
            if case .downloading(let p) = status { seen.append(p) }
        }
        defer { cancellable.cancel() }

        await vm.download(modelName: "openai_whisper-small")

        XCTAssertTrue(seen.contains(0.25))
        XCTAssertTrue(seen.contains(0.75))
    }

    func test_download_success_recordsPathInSettings_andShowsDoneMessage() async {
        let downloader = MockModelDownloader()
        downloader.result = .success(URL(fileURLWithPath: "/models/small"))
        let settings = makeSettings()
        let vm = ModelDownloadViewModel(downloader: downloader, settings: settings)

        await vm.download(modelName: "openai_whisper-small")

        XCTAssertEqual(settings.modelFolderPath(for: "openai_whisper-small"), "/models/small")
        guard case .done = vm.status else {
            return XCTFail("expected .done, got \(vm.status)")
        }
    }

    func test_download_failure_showsErrorMessage_andAllowsRetry() async {
        let downloader = MockModelDownloader()
        downloader.result = .failure(URLError(.notConnectedToInternet))
        let vm = ModelDownloadViewModel(downloader: downloader, settings: makeSettings())

        await vm.download(modelName: "m")
        guard case .failed = vm.status else {
            return XCTFail("expected .failed, got \(vm.status)")
        }

        // A failure leaves the VM idle-capable — a retry can run.
        downloader.result = .success(URL(fileURLWithPath: "/models/m"))
        await vm.download(modelName: "m")
        guard case .done = vm.status else {
            return XCTFail("retry should succeed, got \(vm.status)")
        }
    }

    func test_download_preventsConcurrentDownloads() async {
        let downloader = MockModelDownloader()
        downloader.holdUntilReleased = true
        let vm = ModelDownloadViewModel(downloader: downloader, settings: makeSettings())

        let first = Task { await vm.download(modelName: "m") }
        // Wait until the first download is in-flight (suspended at the gate).
        while downloader.downloadCallCount == 0 { await Task.yield() }

        await vm.download(modelName: "m")   // should be a no-op while downloading
        XCTAssertEqual(downloader.downloadCallCount, 1)

        downloader.release()
        await first.value
    }
}
