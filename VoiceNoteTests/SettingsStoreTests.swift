import XCTest
@testable import VoiceNote

/// `SettingsStore` 全部以隔離的 `UserDefaults` suite 測試，
/// 避免汙染正式偏好設定，也讓每個測試互不相依。
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    // MARK: - selectedModel

    func test_selectedModel_defaultsToLargeV3Turbo() {
        XCTAssertEqual(makeStore().selectedModel, "openai_whisper-large-v3_turbo")
    }

    func test_selectedModel_persistsAcrossInstances() {
        let store1 = makeStore()
        store1.selectedModel = "openai_whisper-small"

        let store2 = makeStore()
        XCTAssertEqual(store2.selectedModel, "openai_whisper-small")
    }

    // MARK: - 模型名稱遷移

    func test_migration_mapsAllLegacyModelNames() {
        let expected: [String: String] = [
            "tiny": "openai_whisper-small",
            "base": "openai_whisper-small",
            "small": "openai_whisper-small",
            "medium": "openai_whisper-large-v3_turbo_954MB",
            "large-v2": "openai_whisper-large-v3_turbo_954MB",
            "large-v3": "openai_whisper-large-v3",
            "large-v3-turbo": "openai_whisper-large-v3_turbo",
            "openai_whisper-large-v2": "openai_whisper-large-v3_turbo_954MB",
        ]

        for (legacy, mapped) in expected {
            defaults.set(legacy, forKey: "selectedModel")
            XCTAssertEqual(
                makeStore().selectedModel, mapped,
                "legacy \(legacy) should migrate to \(mapped)"
            )
        }
    }

    func test_migration_writesBackMigratedName() {
        defaults.set("large-v3", forKey: "selectedModel")

        // 觸發 getter → 應回寫遷移後的名稱到底層 defaults。
        XCTAssertEqual(makeStore().selectedModel, "openai_whisper-large-v3")
        XCTAssertEqual(defaults.string(forKey: "selectedModel"), "openai_whisper-large-v3")
    }

    func test_migration_leavesUnknownNamesUntouched() {
        defaults.set("openai_whisper-large-v3_turbo", forKey: "selectedModel")

        XCTAssertEqual(makeStore().selectedModel, "openai_whisper-large-v3_turbo")
        XCTAssertEqual(
            defaults.string(forKey: "selectedModel"),
            "openai_whisper-large-v3_turbo"
        )
    }

    // MARK: - 其他設定預設值

    func test_autoProofread_defaultsToFalse() {
        XCTAssertFalse(makeStore().autoProofread)
    }

    func test_chineseVariant_defaultsToTraditional() {
        XCTAssertEqual(makeStore().chineseVariant, "zh-Hant")
    }

    func test_pasteAtCursor_defaultsToTrue() {
        XCTAssertTrue(makeStore().pasteAtCursor)
    }

    func test_decodingParameters_defaults() {
        let store = makeStore()
        XCTAssertEqual(store.decodingTopK, 5)
        XCTAssertEqual(store.decodingTemperature, 0.0)
        XCTAssertEqual(store.decodingFallbackCount, 5)
    }

    // MARK: - set → get round-trip

    func test_autoProofread_roundTrip() {
        let store = makeStore()
        store.autoProofread = true
        XCTAssertTrue(store.autoProofread)
    }

    func test_chineseVariant_roundTrip() {
        let store = makeStore()
        store.chineseVariant = "zh-Hans"
        XCTAssertEqual(store.chineseVariant, "zh-Hans")
    }

    func test_pasteAtCursor_roundTrip() {
        let store = makeStore()
        store.pasteAtCursor = false
        XCTAssertFalse(store.pasteAtCursor)
    }

    func test_decodingTopK_roundTrip() {
        let store = makeStore()
        store.decodingTopK = 12
        XCTAssertEqual(store.decodingTopK, 12)
    }

    func test_decodingTemperature_roundTrip() {
        let store = makeStore()
        store.decodingTemperature = 0.7
        XCTAssertEqual(store.decodingTemperature, 0.7)
    }

    func test_decodingFallbackCount_roundTrip() {
        let store = makeStore()
        store.decodingFallbackCount = 3
        XCTAssertEqual(store.decodingFallbackCount, 3)
    }
}
