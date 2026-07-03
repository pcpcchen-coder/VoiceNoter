import XCTest
@testable import VoiceNote

final class DecodingSettingsTests: XCTestCase {

    func test_defaults_matchLegacyValues() {
        let d = DecodingSettings()
        XCTAssertEqual(d.language, "zh")
        XCTAssertEqual(d.topK, 5)
        XCTAssertEqual(d.temperature, 0)
        XCTAssertEqual(d.temperatureFallbackCount, 5)
        XCTAssertNil(d.prompt)
        XCTAssertEqual(d.variant, .traditional)
    }

    func test_init_fromSettingsStore() {
        let defaults = UserDefaults(suiteName: "DecodingSettingsTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.decodingTopK = 9
        store.decodingTemperature = 0.4
        store.decodingFallbackCount = 2
        store.chineseVariant = .simplified

        let d = DecodingSettings(settings: store, prompt: "EMS, PCS")

        XCTAssertEqual(d.topK, 9)
        XCTAssertEqual(d.temperature, 0.4)
        XCTAssertEqual(d.temperatureFallbackCount, 2)
        XCTAssertEqual(d.variant, .simplified)
        XCTAssertEqual(d.prompt, "EMS, PCS")
        XCTAssertEqual(d.language, "zh")
    }

    func test_init_fromSettingsStore_nilPrompt() {
        let defaults = UserDefaults(suiteName: "DecodingSettingsTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)

        let d = DecodingSettings(settings: store, prompt: nil)

        XCTAssertNil(d.prompt)
        XCTAssertEqual(d.topK, 5)
        XCTAssertEqual(d.variant, .traditional)
    }
}
