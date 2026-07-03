import XCTest
@testable import VoiceNote

final class CredentialMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "CredentialMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_migration_movesLegacyTokenFromDefaultsToStore() throws {
        defaults.set("legacy-token", forKey: "openai_access_token")
        defaults.set("legacy-refresh", forKey: "openai_refresh_token")
        let store = InMemoryCredentialStore()

        let migrated = migrateLegacyToken(defaults: defaults, into: store)

        XCTAssertTrue(migrated)
        XCTAssertEqual(store.apiKey, "legacy-token")
        XCTAssertNil(defaults.string(forKey: "openai_access_token"))
        XCTAssertNil(defaults.string(forKey: "openai_refresh_token"))
    }

    func test_migration_skipsWhenNoLegacyToken() {
        let store = InMemoryCredentialStore()

        let migrated = migrateLegacyToken(defaults: defaults, into: store)

        XCTAssertFalse(migrated)
        XCTAssertNil(store.apiKey)
    }

    func test_migration_doesNotOverwriteExistingStoreValue() throws {
        defaults.set("new-token", forKey: "openai_access_token")
        let store = InMemoryCredentialStore()
        try store.set("existing")

        let migrated = migrateLegacyToken(defaults: defaults, into: store)

        XCTAssertFalse(migrated)
        XCTAssertEqual(store.apiKey, "existing")
        // 殘留的舊 defaults token 仍應被清掉。
        XCTAssertNil(defaults.string(forKey: "openai_access_token"))
    }

    func test_inMemoryStore_setGetClearRoundTrip() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(store.apiKey)

        try store.set("abc")
        XCTAssertEqual(store.apiKey, "abc")

        try store.set("")   // 空字串視為清除
        XCTAssertNil(store.apiKey)

        try store.set("def")
        try store.clear()
        XCTAssertNil(store.apiKey)
    }
}
