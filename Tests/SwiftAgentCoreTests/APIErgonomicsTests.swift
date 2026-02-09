import AnyLanguageModel
import Foundation
import Testing

@testable import SwiftAgentCore

@Test("Agent convenience initializer generates id and preserves fields")
func agentConvenienceInitializer() {
    let agent = Agent(
        name: "Convenience Agent",
        description: "Test",
        modelName: "test-model",
        instructions: "Be helpful",
        toolNames: ["tool-a"],
        mcpServerNames: ["mcp-a"],
        preHookNames: ["pre-a"],
        postHookNames: ["post-a"]
    )

    #expect(!agent.id.isEmpty)
    #expect(agent.name == "Convenience Agent")
    #expect(agent.modelName == "test-model")
    #expect(agent.instructions == "Be helpful")
    #expect(agent.toolNames == ["tool-a"])
    #expect(agent.mcpServerNames == ["mcp-a"])
    #expect(agent.preHookNames == ["pre-a"])
    #expect(agent.postHookNames == ["post-a"])
}

@Test("AgentCenter runAgent convenience overload returns string run")
func runAgentConvenienceOverload() async throws {
    let center = LiveAgentCenter()

    let model = createAPIErgonomicsMockModel()
    await center.register(model: model, named: "test-model")

    let agent = Agent(
        name: "Convenience Runner",
        description: "Test",
        modelName: "test-model",
        instructions: "Be helpful"
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

    let run = try await center.runAgent(
        session: context,
        message: "hello"
    )

    let text = try run.asString()
    #expect(text.contains("Mock response for API ergonomics tests"))
}

private func createAPIErgonomicsMockModel() -> any LanguageModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [APIErgonomicsURLProtocol.self]
    let session = URLSession(configuration: configuration)

    return OpenAILanguageModel(
        baseURL: URL(string: "https://mock.local/v1")!,
        apiKey: "test-key",
        model: "gpt-4",
        session: session
    )
}

private final class APIErgonomicsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseBody = """
            {
              "id": "chatcmpl-api-ergonomics",
              "object": "chat.completion",
              "created": 1730000000,
              "model": "gpt-4",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "Mock response for API ergonomics tests"
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15
              }
            }
            """

        let data = Data(responseBody.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.local/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
