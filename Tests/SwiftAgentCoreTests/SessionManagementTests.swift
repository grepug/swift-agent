import Foundation
import Testing

@testable import SwiftAgentCore

@Test func testSessionMustExistBeforeRunning() async throws {
    let storage = InMemoryAgentStorage()

    // Try to append a run to a non-existent session
    let run = Run(
        agentId: "test-agent",
        sessionId: UUID(),  // This session doesn't exist
        userId: UUID(),
        messages: []
    )

    await #expect(throws: StorageError.self) {
        try await storage.appendRun(run, sessionId: run.sessionId)
    }
}

@Test func testCreateSessionInAgentCenter() async throws {
    let center = LiveAgentCenter()

    // Register an agent
    let agent = Agent(
        id: "test-agent",
        name: "Test Agent",
        description: "A test agent",
        modelName: "test-model",
        instructions: "You are a helpful assistant"
    )
    await center.register(agent: agent)

    // Create a session
    let userId = UUID()
    let session = try await center.createSession(
        agentId: "test-agent",
        userId: userId,
        name: "Test Session"
    )

    #expect(session.agentId == "test-agent")
    #expect(session.userId == userId)
    #expect(session.name == "Test Session")
    #expect(session.messages.isEmpty)
    #expect(session.runs.isEmpty)
}

@Test func testCreateSessionForNonExistentAgentFails() async throws {
    let center = LiveAgentCenter()

    await #expect(throws: AgentError.self) {
        _ = try await center.createSession(
            agentId: "non-existent",
            userId: UUID(),
            name: "Test"
        )
    }
}
