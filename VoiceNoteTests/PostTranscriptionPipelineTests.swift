import XCTest
@testable import VoiceNote

@MainActor
final class PostTranscriptionPipelineTests: XCTestCase {

    private func makeSUT() -> (PostTranscriptionPipeline, AppState, MockRewriter, MockNoteStore) {
        let defaults = UserDefaults(suiteName: "PTP-\(UUID().uuidString)")!
        let state = AppState(settings: SettingsStore(defaults: defaults))
        let rewriter = MockRewriter()
        let noteStore = MockNoteStore()
        let pipeline = PostTranscriptionPipeline(rewriter: rewriter, noteStore: noteStore, state: state)
        return (pipeline, state, rewriter, noteStore)
    }

    func test_detectOrganizeCommand_matchesTriggerPhrases() {
        XCTAssertTrue(PostTranscriptionPipeline.detectOrganizeCommand("幫我整理一下今天"))
        XCTAssertTrue(PostTranscriptionPipeline.detectOrganizeCommand("請整理筆記"))
        XCTAssertFalse(PostTranscriptionPipeline.detectOrganizeCommand("今天天氣很好"))
    }

    // MARK: - proofread

    func test_proofread_replacesLastEntry_andSetsInfoMessage() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()
        rewriter.result = .success("校稿後內容")

        await pipeline.proofread(original: "原始逐字稿", enabled: true)

        XCTAssertEqual(noteStore.replaceCalls.count, 1)
        XCTAssertEqual(noteStore.replaceCalls.first?.original, "原始逐字稿")
        XCTAssertEqual(noteStore.replaceCalls.first?.replacement, "校稿後內容")
        XCTAssertEqual(state.infoMessage, "已自動校稿")
        XCTAssertNil(state.lastError)
    }

    func test_proofread_failure_setsLastError_keepsOriginalNote() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()
        rewriter.result = .failure(OpenAIRewriterError.missingAPIKey)

        await pipeline.proofread(original: "原始", enabled: true)

        XCTAssertTrue(state.lastError?.hasPrefix("AI 校稿失敗") == true)
        XCTAssertNil(state.infoMessage)
        XCTAssertTrue(noteStore.replaceCalls.isEmpty, "note must not be touched when rewrite fails")
    }

    func test_proofread_disabled_doesNothing() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()

        await pipeline.proofread(original: "原始", enabled: false)

        XCTAssertTrue(rewriter.calls.isEmpty)
        XCTAssertTrue(noteStore.replaceCalls.isEmpty)
        XCTAssertNil(state.infoMessage)
        XCTAssertNil(state.lastError)
    }

    // MARK: - organize

    func test_organize_appendsSummarySection_preservesOriginalContent() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()
        let original = "# 2026-05-02\n\n## 09:00:00\n\n早上的筆記\n"
        noteStore.readResult = .success(original)
        rewriter.result = .success("整理後摘要")

        await pipeline.organize()

        // 原文完整送去整理（保留、不覆蓋）。
        XCTAssertEqual(rewriter.calls.first, original)
        // 摘要以新段落追加，未觸碰原內容。
        XCTAssertEqual(noteStore.appendedSections.count, 1)
        XCTAssertTrue(noteStore.appendedSections.first?.title.contains("AI 整理") == true)
        XCTAssertEqual(noteStore.appendedSections.first?.body, "整理後摘要")
        XCTAssertTrue(noteStore.replaceCalls.isEmpty)
        XCTAssertEqual(state.infoMessage, "筆記已由 AI 整理")
    }

    func test_organize_emptyNote_doesNothing() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()
        noteStore.readResult = .success("   \n")

        await pipeline.organize()

        XCTAssertTrue(rewriter.calls.isEmpty)
        XCTAssertTrue(noteStore.appendedSections.isEmpty)
        XCTAssertNotNil(state.lastError)
    }

    func test_organize_failure_setsLastError() async {
        let (pipeline, state, rewriter, noteStore) = makeSUT()
        noteStore.readResult = .success("有內容")
        rewriter.result = .failure(OpenAIRewriterError.decodingFailed)

        await pipeline.organize()

        XCTAssertTrue(state.lastError?.hasPrefix("AI 整理失敗") == true)
        XCTAssertTrue(noteStore.appendedSections.isEmpty)
    }
}
