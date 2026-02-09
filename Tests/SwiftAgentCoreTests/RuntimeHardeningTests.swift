import Foundation
import Testing

@testable import SwiftAgentCore

@Test("runAgent throws modelNotFound instead of crashing when model is missing")
func runAgentThrowsModelNotFoundForMissingModel() async throws {
    let center = LiveAgentCenter()

    let agent = Agent(
        id: "missing-model-agent",
        name: "Missing Model Agent",
        description: "Test agent",
        modelName: "missing-model",
        instructions: "You are a helpful assistant"
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

    do {
        _ = try await center.runAgent(
            session: context,
            message: "hello",
            as: String.self,
            loadHistory: false
        )
        Issue.record("Expected AgentError.modelNotFound")
    } catch let error as AgentError {
        switch error {
        case .modelNotFound(let name):
            #expect(name == "missing-model")
        default:
            Issue.record("Expected modelNotFound, got: \(error)")
        }
    } catch {
        Issue.record("Expected AgentError, got: \(error)")
    }
}

@Test("Run.asString throws invalidUTF8Data for non-UTF8 payload")
func runAsStringThrowsForInvalidUTF8() throws {
    let run = Run(
        agentId: "test-agent",
        sessionId: UUID(),
        userId: UUID(),
        messages: [],
        rawContent: Data([0xFF, 0xFE, 0xFD])
    )

    do {
        _ = try run.asString()
        Issue.record("Expected RunError.invalidUTF8Data")
    } catch let error as RunError {
        switch error {
        case .invalidUTF8Data:
            #expect(Bool(true))
        default:
            Issue.record("Expected invalidUTF8Data, got: \(error)")
        }
    } catch {
        Issue.record("Expected RunError, got: \(error)")
    }
}
