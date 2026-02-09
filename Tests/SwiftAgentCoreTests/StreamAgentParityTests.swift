import AnyLanguageModel
import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

@Test("streamAgent emits deltas, persists run, and executes hooks")
func streamAgentParity() async throws {
    let storage = InMemoryAgentStorage()
    let postHookRunID = LockIsolated<UUID?>(nil)

    try await withDependencies {
        $0.storage = storage
    } operation: {
        let center = LiveAgentCenter()

        await center.register(model: createStreamingMockOpenAIModel(), named: "stream-model")

        let preHook = RegisteredPreHook(name: "prefix", blocking: true) { context in
            context.userMessage = "[pre] \(context.userMessage)"
        }

        let postHook = RegisteredPostHook(name: "capture-run", blocking: true) { _, run in
            postHookRunID.setValue(run.id)
        }

        await center.register(preHook: preHook)
        await center.register(postHook: postHook)

        let agent = Agent(
            name: "Stream Agent",
            description: "Streaming parity test",
            modelName: "stream-model",
            instructions: "Be concise",
            preHookNames: ["prefix"],
            postHookNames: ["capture-run"]
        )
        await center.register(agent: agent)

        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )

        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )

        let stream = await center.streamAgent(
            session: context,
            message: "hello",
            loadHistory: false
        )

        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(chunks == ["Hel", "lo", " world"])

        let savedSession = try await storage.getSession(
            sessionId: session.id,
            agentId: agent.id,
            userId: session.userId
        )

        #expect(savedSession != nil)
        #expect(savedSession?.runs.count == 1)

        let run = try #require(savedSession?.runs.first)
        #expect(try run.asString() == "Hello world")
        #expect(run.messages.contains { $0.role == .user && $0.content == "[pre] hello" })
        #expect(postHookRunID.value == run.id)
    }
}

private func createStreamingMockOpenAIModel() -> any LanguageModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StreamingChatCompletionsURLProtocol.self]
    let session = URLSession(configuration: configuration)

    return OpenAILanguageModel(
        baseURL: URL(string: "https://mock.local/v1")!,
        apiKey: "test-key",
        model: "gpt-4",
        apiVariant: .chatCompletions,
        session: session
    )
}

private final class StreamingChatCompletionsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sse = """
            data: {"id":"chatcmpl-stream-test","choices":[{"delta":{"role":"assistant","content":"Hel"},"finish_reason":null}]}

            data: {"id":"chatcmpl-stream-test","choices":[{"delta":{"content":"lo"},"finish_reason":null}]}

            data: {"id":"chatcmpl-stream-test","choices":[{"delta":{"content":" world"},"finish_reason":"stop"}]}

            data: [DONE]

            """

        let data = Data(sse.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.local/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
