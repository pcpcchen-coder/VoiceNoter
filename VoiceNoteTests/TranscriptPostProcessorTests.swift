import XCTest
@testable import VoiceNote

final class TranscriptPostProcessorTests: XCTestCase {

    func test_process_convertsSimplifiedToTraditional() {
        let result = TranscriptPostProcessor.process(segments: ["语音转录"], variant: .traditional)
        XCTAssertEqual(result, "語音轉錄")
    }

    func test_process_convertsTraditionalToSimplified() {
        let result = TranscriptPostProcessor.process(segments: ["語音轉錄"], variant: .simplified)
        XCTAssertEqual(result, "语音转录")
    }

    func test_process_trimsWhitespaceAndNewlines() {
        let result = TranscriptPostProcessor.process(segments: ["  hello \n"], variant: .traditional)
        XCTAssertEqual(result, "hello")
    }

    func test_process_joinsMultipleSegmentsWithSpace() {
        let result = TranscriptPostProcessor.process(segments: ["前段", "後段"], variant: .traditional)
        XCTAssertEqual(result, "前段 後段")
    }

    func test_process_returnsNilForEmptyResult() {
        XCTAssertNil(TranscriptPostProcessor.process(segments: [], variant: .traditional))
        XCTAssertNil(TranscriptPostProcessor.process(segments: ["  ", "\n"], variant: .traditional))
    }

    // MARK: - ChineseVariant 契約

    func test_chineseVariant_rawValuesMatchLegacyStrings() {
        // 這些字串是 UserDefaults 的持久化格式，不可更動，否則舊使用者設定會失效。
        XCTAssertEqual(ChineseVariant.traditional.rawValue, "zh-Hant")
        XCTAssertEqual(ChineseVariant.simplified.rawValue, "zh-Hans")
        XCTAssertEqual(ChineseVariant(rawValue: "zh-Hant"), .traditional)
        XCTAssertEqual(ChineseVariant(rawValue: "zh-Hans"), .simplified)
    }

    func test_chineseVariant_rawValueOrDefault_fallsBackToTraditional() {
        XCTAssertEqual(ChineseVariant(rawValueOrDefault: nil), .traditional)
        XCTAssertEqual(ChineseVariant(rawValueOrDefault: "not-a-variant"), .traditional)
        XCTAssertEqual(ChineseVariant(rawValueOrDefault: "zh-Hans"), .simplified)
    }
}
