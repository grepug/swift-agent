import AnyLanguageModel
import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

@Test("context-window trims history by message count")
func contextWindowTrimsByMessageCount() async throws {
    let storage = InMemoryAgentStorage()
    let observedTranscriptCounts = LockIsolated<[Int]>([])

    let observer = CapturingObserver { event in
        guard case .modelRequestSending(_, let transcript, _, _, _, _, _) = event else { return }
        observedTranscriptCounts.withValue { values in
            values.append(transcript.count)
        }
    }

    try await withDependencies {
        $0.storage = storage
        $0.agentObservers = [observer]
    } operation: {
        let center = LiveAgentCenter()
        await center.register(model: makeContextWindowModel(), named: "count-model")

        let agent = Agent(
            name: "Context Window Count Agent",
            description: "Count window",
            modelName: "count-model",
            instructions: "Be concise"
        )
        await center.register(agent: agent)

        let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
        let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

        _ = try await center.runAgent(session: context, message: "u1", loadHistory: true, executionPolicy: .default)
        _ = try await center.runAgent(session: context, message: "u2", loadHistory: true, executionPolicy: .default)

        _ = try await center.runAgent(
            session: context,
            message: "u3",
            loadHistory: true,
            executionPolicy: ExecutionPolicy(maxHistoryMessages: 2)
        )
    }

    let counts = observedTranscriptCounts.value
    #expect(counts.count == 3)
    guard counts.count == 3 else { return }

    #expect(counts[0] == 2)
    #expect(counts[1] == 4)
    #expect(counts[2] == 4)
}

@Test("context-window trims history by token budget")
func contextWindowTrimsByTokenBudget() async throws {
    let storage = InMemoryAgentStorage()
    let observedTranscriptCounts = LockIsolated<[Int]>([])

    let observer = CapturingObserver { event in
        guard case .modelRequestSending(_, let transcript, _, _, _, _, _) = event else { return }
        observedTranscriptCounts.withValue { values in
            values.append(transcript.count)
        }
    }

    try await withDependencies {
        $0.storage = storage
        $0.agentObservers = [observer]
    } operation: {
        let center = LiveAgentCenter()
        await center.register(model: makeContextWindowModel(), named: "token-model")

        let agent = Agent(
            name: "Context Window Token Agent",
            description: "Token window",
            modelName: "token-model",
            instructions: "Be concise"
        )
        await center.register(agent: agent)

        let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
        let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

        _ = try await center.runAgent(session: context, message: "this is a very long first user message", loadHistory: true, executionPolicy: .default)
        _ = try await center.runAgent(session: context, message: "another long user message to grow context", loadHistory: true, executionPolicy: .default)

        _ = try await center.runAgent(
            session: context,
            message: "final message",
            loadHistory: true,
            executionPolicy: ExecutionPolicy(maxHistoryTokens: 1)
        )
    }

    let counts = observedTranscriptCounts.value
    #expect(counts.count == 3)
    guard counts.count == 3 else { return }

    #expect(counts[2] == 3)
}

@Test("summary hook updates session summary when context-window drops history")
func summaryHookUpdatesSessionSummary() async throws {
    let storage = InMemoryAgentStorage()
    let summarySeenInRequest = LockIsolated(false)

    let observer = CapturingObserver { event in
        guard case .modelRequestSending(_, let transcript, _, _, _, _, _) = event else { return }
        if transcriptContainsSummary(transcript, expected: "Dropped 1 messages") {
            summarySeenInRequest.setValue(true)
        }
    }

    try await withDependencies {
        $0.storage = storage
        $0.agentObservers = [observer]
    } operation: {
        let center = LiveAgentCenter()
        await center.register(model: makeContextWindowModel(), named: "summary-model")

        let summaryHook = RegisteredSummaryHook(name: "compact-summary") { context in
            "Dropped \(context.droppedMessages.count) messages"
        }
        await center.register(summaryHook: summaryHook)

        let agent = Agent(
            name: "Context Window Summary Agent",
            description: "Summary window",
            modelName: "summary-model",
            instructions: "Be concise"
        )
        await center.register(agent: agent)

        let session = try await center.createSession(agentId: agent.id, userId: UUID(), name: nil)
        let context = AgentSessionContext(agentId: agent.id, userId: session.userId, sessionId: session.id)

        _ = try await center.runAgent(session: context, message: "hello one", loadHistory: true, executionPolicy: .default)

        _ = try await center.runAgent(
            session: context,
            message: "hello two",
            loadHistory: true,
            executionPolicy: ExecutionPolicy(maxHistoryMessages: 1, summaryHookName: "compact-summary")
        )

        let persistedSession = try await storage.getSession(
            sessionId: session.id,
            agentId: agent.id,
            userId: session.userId
        )

        #expect(persistedSession?.summary == "Dropped 1 messages")
    }

    #expect(summarySeenInRequest.value)
}

private func transcriptContainsSummary(_ transcript: Transcript, expected: String) -> Bool {
    transcript.contains { entry in
        guard case .instructions(let instructions) = entry else { return false }
        return instructions.segments.contains { segment in
            guard case .text(let text) = segment else { return false }
            return text.content.contains("Conversation summary") && text.content.contains(expected)
        }
    }
}

private func makeContextWindowModel() -> any LanguageModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ContextWindowResponseURLProtocol.self]
    let session = URLSession(configuration: configuration)

    return OpenAILanguageModel(
        baseURL: URL(string: "https://mock.local/v1")!,
        apiKey: "test-key",
        model: "gpt-4",
        session: session
    )
}

private final class CapturingObserver: AgentCenterObserver, @unchecked Sendable {
    private let onEvent: @Sendable (AgentCenterEvent) -> Void

    init(_ onEvent: @escaping @Sendable (AgentCenterEvent) -> Void) {
        self.onEvent = onEvent
    }

    func observe(_ event: AgentCenterEvent) {
        onEvent(event)
    }
}

private final class ContextWindowResponseURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let responseBody = """
            {
              "id": "chatcmpl-context-window",
              "object": "chat.completion",
              "created": 1730000000,
              "model": "gpt-4",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "ok"
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 2,
                "total_tokens": 12
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
