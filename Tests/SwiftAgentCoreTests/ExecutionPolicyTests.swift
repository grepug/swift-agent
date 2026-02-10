import AnyLanguageModel
import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

@Test("runAgent retries once after transient failure")
func runAgentRetriesOnFailure() async throws {
    RetryChatCompletionsURLProtocol.reset()

    let center = LiveAgentCenter()
    await center.register(model: makeOpenAIMockModel(protocolClass: RetryChatCompletionsURLProtocol.self), named: "retry-model")

    let agent = Agent(
        name: "Retry Agent",
        description: "Retries",
        modelName: "retry-model",
        instructions: "Be concise"
    )
    await center.register(agent: agent)

    let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
    let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

    let run = try await center.runAgent(
        session: context,
        message: "hello",
        loadHistory: false,
        executionPolicy: ExecutionPolicy(retries: 1)
    )

    #expect(try run.asString() == "retry-success")
    #expect(RetryChatCompletionsURLProtocol.attemptCount == 2)
}

@Test("runAgent timeout throws executionTimedOut")
func runAgentTimeout() async throws {
    let center = LiveAgentCenter()
    await center.register(model: makeOpenAIMockModel(protocolClass: SlowChatCompletionsURLProtocol.self), named: "slow-model")

    let agent = Agent(
        name: "Timeout Agent",
        description: "Timeout",
        modelName: "slow-model",
        instructions: "Be concise"
    )
    await center.register(agent: agent)

    let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
    let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

    do {
        _ = try await center.runAgent(
            session: context,
            message: "hello",
            loadHistory: false,
            executionPolicy: ExecutionPolicy(timeout: 0.05)
        )
        Issue.record("Expected AgentError.executionTimedOut")
    } catch let error as AgentError {
        switch error {
        case .executionTimedOut(let timeout):
            #expect(timeout == 0.05)
        default:
            Issue.record("Expected executionTimedOut, got: \(error)")
        }
    }
}

@Test("runAgent applies maxToolCalls to OpenAI Responses API")
func runAgentAppliesMaxToolCallsOption() async throws {
    ResponsesMaxToolCallsURLProtocol.reset()

    let center = LiveAgentCenter()
    await center.register(
        model: makeOpenAIMockModel(
            protocolClass: ResponsesMaxToolCallsURLProtocol.self,
            apiVariant: .responses
        ),
        named: "options-model"
    )

    let agent = Agent(
        name: "Options Agent",
        description: "Options",
        modelName: "options-model",
        instructions: "Be concise"
    )
    await center.register(agent: agent)

    let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
    let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

    let run = try await center.runAgent(
        session: context,
        message: "hello",
        loadHistory: false,
        executionPolicy: ExecutionPolicy(maxToolCalls: 3)
    )

    #expect(try run.asString() == "ok")
    #expect(ResponsesMaxToolCallsURLProtocol.capturedMaxToolCalls == 3)
}

private func makeOpenAIMockModel(
    protocolClass: URLProtocol.Type,
    apiVariant: OpenAILanguageModel.APIVariant = .chatCompletions
) -> any LanguageModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    let session = URLSession(configuration: configuration)

    return OpenAILanguageModel(
        baseURL: URL(string: "https://mock.local/v1")!,
        apiKey: "test-key",
        model: "gpt-4",
        apiVariant: apiVariant,
        session: session
    )
}

private final class RetryChatCompletionsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let attempts = LockIsolated(0)

    static var attemptCount: Int { attempts.value }

    static func reset() {
        attempts.setValue(0)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let attempt = Self.attempts.withValue { value in
            value += 1
            return value
        }

        if attempt == 1 {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }

        let responseBody = """
            {
              "id": "chatcmpl-retry",
              "object": "chat.completion",
              "created": 1730000000,
              "model": "gpt-4",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "retry-success"
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 3,
                "total_tokens": 13
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

private final class SlowChatCompletionsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Thread.sleep(forTimeInterval: 0.3)

        let responseBody = """
            {
              "id": "chatcmpl-slow",
              "object": "chat.completion",
              "created": 1730000001,
              "model": "gpt-4",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "too-late"
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 8,
                "completion_tokens": 2,
                "total_tokens": 10
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

private final class ResponsesMaxToolCallsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let maxToolCalls = LockIsolated<Int?>(nil)

    static var capturedMaxToolCalls: Int? { maxToolCalls.value }

    static func reset() {
        maxToolCalls.setValue(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = request.httpBody ?? Self.readBodyData(from: request.httpBodyStream)
        if let bodyData,
            let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        {
            let capturedValue = json["max_tool_calls"] as? Int
            Self.maxToolCalls.setValue(capturedValue)
        }

        let responseBody = """
            {
              "id": "resp-max-tool-calls",
              "output_text": "ok",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "ok"
                    }
                  ]
                }
              ],
              "usage": {
                "prompt_tokens": 9,
                "completion_tokens": 1,
                "total_tokens": 10
              }
            }
            """

        let data = Data(responseBody.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.local/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyData(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            if bytesRead <= 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }
}
