import AnyLanguageModel
import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

@Suite("Run Options Tests", .serialized)
struct RunOptionsTests {
    @Test("runAgent applies generation options and tool filtering")
    func runAgentAppliesGenerationAndToolFiltering() async throws {
        let storage = InMemoryAgentStorage()
        RunOptionsURLProtocol.reset()

        try await withDependencies {
            $0.storage = storage
        } operation: {
            let center = LiveAgentCenter()
            await center.register(model: createRunOptionsMockModel(), named: "run-options-model")
            await center.register(tool: AlphaTool())
            await center.register(tool: BetaTool())

            let agent = Agent(
                name: "Run Options Agent",
                description: "Tests per-run options",
                modelName: "run-options-model",
                instructions: "Keep answers short.",
                toolNames: ["alpha_tool", "beta_tool"]
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

            let options = AgentRunOptions(
                generationOptions: GenerationOptions(
                    temperature: 0.42,
                    maximumResponseTokens: 111
                ),
                allowedToolNames: ["alpha_tool"],
                blockedToolNames: ["beta_tool"]
            )

            _ = try await center.runAgent(
                session: context,
                message: "hello",
                as: String.self,
                options: options,
                loadHistory: false
            )

            let payload = try #require(Self.latestRequestPayload())
            #expect(payload["temperature"] as? Double == 0.42)
            #expect(payload["max_completion_tokens"] as? Int == 111)

            let toolNames = Self.extractToolNames(from: payload)
            #expect(toolNames == ["alpha_tool"])
        }
    }

    @Test("streamAgent applies generation options and tool filtering")
    func streamAgentAppliesGenerationAndToolFiltering() async throws {
        let storage = InMemoryAgentStorage()
        RunOptionsURLProtocol.reset()

        try await withDependencies {
            $0.storage = storage
        } operation: {
            let center = LiveAgentCenter()
            await center.register(model: createRunOptionsMockModel(), named: "run-options-model-stream")
            await center.register(tool: AlphaTool())
            await center.register(tool: BetaTool())

            let agent = Agent(
                name: "Run Options Stream Agent",
                description: "Tests stream run options",
                modelName: "run-options-model-stream",
                instructions: "Keep answers short.",
                toolNames: ["alpha_tool", "beta_tool"]
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

            let options = AgentRunOptions(
                generationOptions: GenerationOptions(
                    temperature: 0.31,
                    maximumResponseTokens: 222
                ),
                allowedToolNames: ["beta_tool"]
            )

            let stream = await center.streamAgent(
                session: context,
                message: "stream hello",
                options: options,
                loadHistory: false
            )

            var chunks: [String] = []
            for try await chunk in stream {
                chunks.append(chunk)
            }
            #expect(chunks == ["Hel", "lo world"])

            let payload = try #require(Self.latestRequestPayload())
            #expect(payload["temperature"] as? Double == 0.31)
            #expect(payload["max_completion_tokens"] as? Int == 222)
            #expect(payload["stream"] as? Bool == true)

            let toolNames = Self.extractToolNames(from: payload)
            #expect(toolNames == ["beta_tool"])
        }
    }

    @Test("runAgent throws for unknown allowed tool")
    func runAgentThrowsForUnknownAllowedTool() async throws {
        let storage = InMemoryAgentStorage()
        RunOptionsURLProtocol.reset()

        try await withDependencies {
            $0.storage = storage
        } operation: {
            let center = LiveAgentCenter()
            await center.register(model: createRunOptionsMockModel(), named: "run-options-model-invalid")
            await center.register(tool: AlphaTool())

            let agent = Agent(
                name: "Run Options Validation Agent",
                description: "Tests invalid run options",
                modelName: "run-options-model-invalid",
                instructions: "Keep answers short.",
                toolNames: ["alpha_tool"]
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

            let options = AgentRunOptions(allowedToolNames: ["missing_tool"])

            await #expect(throws: AgentError.self) {
                _ = try await center.runAgent(
                    session: context,
                    message: "hello",
                    as: String.self,
                    options: options,
                    loadHistory: false
                )
            }
        }
    }
}

private extension RunOptionsTests {
    static func latestRequestPayload() -> [String: Any]? {
        guard let body = RunOptionsURLProtocol.capturedRequestBodies.value.last else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func extractToolNames(from payload: [String: Any]) -> [String] {
        guard let tools = payload["tools"] as? [[String: Any]] else {
            return []
        }

        return tools
            .compactMap { tool in
                (tool["function"] as? [String: Any])?["name"] as? String
            }
            .sorted()
    }
}

private func createRunOptionsMockModel() -> any LanguageModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RunOptionsURLProtocol.self]
    let session = URLSession(configuration: configuration)

    return OpenAILanguageModel(
        baseURL: URL(string: "https://mock.local/v1")!,
        apiKey: "test-key",
        model: "gpt-4",
        apiVariant: .chatCompletions,
        session: session
    )
}

private struct AlphaTool: Tool {
    let name = "alpha_tool"
    let description = "Alpha tool"

    func call(arguments: String) async throws -> String {
        "alpha:\(arguments)"
    }
}

private struct BetaTool: Tool {
    let name = "beta_tool"
    let description = "Beta tool"

    func call(arguments: String) async throws -> String {
        "beta:\(arguments)"
    }
}

private final class RunOptionsURLProtocol: URLProtocol, @unchecked Sendable {
    static let capturedRequestBodies = LockIsolated<[Data]>([])

    static func reset() {
        capturedRequestBodies.setValue([])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = Self.requestBodyData(from: request)
        Self.capturedRequestBodies.withValue { bodies in
            bodies.append(bodyData)
        }

        let isStreamRequest = Self.isStreamRequest(bodyData)
        if isStreamRequest {
            sendStreamResponse()
        } else {
            sendNonStreamResponse()
        }
    }

    override func stopLoading() {}

    private static func isStreamRequest(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stream = object["stream"] as? Bool
        else {
            return false
        }
        return stream
    }

    private static func requestBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount <= 0 {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }

    private func sendNonStreamResponse() {
        let responseBody = """
            {
              "id": "chatcmpl-run-options",
              "object": "chat.completion",
              "created": 1730000000,
              "model": "gpt-4",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "Mock response for run options tests"
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

    private func sendStreamResponse() {
        let sse = """
            data: {"id":"chatcmpl-stream-run-options","choices":[{"delta":{"role":"assistant","content":"Hel"},"finish_reason":null}]}

            data: {"id":"chatcmpl-stream-run-options","choices":[{"delta":{"content":"lo world"},"finish_reason":"stop"}]}

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
}
