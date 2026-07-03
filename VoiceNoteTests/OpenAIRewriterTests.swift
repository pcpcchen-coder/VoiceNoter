import XCTest
@testable import VoiceNote

final class OpenAIRewriterTests: XCTestCase {

    // MARK: - URLProtocol stub

    /// 攔截所有請求，用 handler 回傳假回應，並記錄收到的請求。
    final class StubURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var capturedRequests: [URLRequest] = []

        static func reset() {
            handler = nil
            capturedRequests = []
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.capturedRequests.append(request)
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private struct StubCredentials: CredentialProviding {
        var apiKey: String?
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeRewriter(apiKey: String? = "test-key") -> OpenAIRewriter {
        OpenAIRewriter(
            credentials: StubCredentials(apiKey: apiKey),
            session: makeSession(),
            model: "gpt-4o-mini"
        )
    }

    private static func makeResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }

    private static func successBody(_ content: String) -> Data {
        let json: [String: Any] = ["choices": [["message": ["content": content]]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Tests

    func test_rewrite_throwsMissingAPIKey_whenNoCredential() async {
        StubURLProtocol.handler = { _ in
            XCTFail("should not make a request without an API key")
            throw URLError(.badServerResponse)
        }
        let rewriter = makeRewriter(apiKey: nil)

        await assertThrows(.missingAPIKey) {
            _ = try await rewriter.rewrite("你好")
        }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func test_rewrite_buildsCorrectRequest() async throws {
        StubURLProtocol.handler = { _ in
            (Self.makeResponse(200), Self.successBody("ok"))
        }
        let rewriter = makeRewriter(apiKey: "secret-key")

        _ = try await rewriter.rewrite("原始內容")

        let request = try XCTUnwrap(StubURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")

        let body = try XCTUnwrap(request.bodyData())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(json["temperature"] as? Double, 0.5)
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "原始內容")
    }

    func test_rewrite_parsesSuccessResponse() async throws {
        StubURLProtocol.handler = { _ in
            (Self.makeResponse(200), Self.successBody("  整理後的內容  "))
        }
        let rewriter = makeRewriter()

        let result = try await rewriter.rewrite("原始")
        XCTAssertEqual(result, "整理後的內容")
    }

    func test_rewrite_mapsHTTPErrorWithServerMessage() async {
        let errorJSON = #"{"error":{"message":"Invalid API key"}}"#.data(using: .utf8)!
        StubURLProtocol.handler = { _ in (Self.makeResponse(401), errorJSON) }
        let rewriter = makeRewriter()

        await assertThrows(.http(status: 401, message: "Invalid API key")) {
            _ = try await rewriter.rewrite("原始")
        }
    }

    func test_rewrite_throwsDecodingFailed_onMalformedJSON() async {
        StubURLProtocol.handler = { _ in (Self.makeResponse(200), Data("not json".utf8)) }
        let rewriter = makeRewriter()

        await assertThrows(.decodingFailed) {
            _ = try await rewriter.rewrite("原始")
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: OpenAIRewriterError,
        _ block: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("expected to throw \(expected)", file: file, line: line)
        } catch let error as OpenAIRewriterError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

private extension URLRequest {
    /// URLProtocol 會把 httpBody 轉成 stream，需自 stream 讀回原始 body。
    func bodyData() -> Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
