import Foundation

/// Protocol for storing agent runs and session state
public protocol StorageProtocol: Sendable {
    /// Retrieve all runs for an agent
    func runs(for agent: Agent) async throws -> [Run]

    func removeRun(id: UUID, sessionId: UUID) async throws

    /// Append a new run for an agent
    func append(_ run: Run, for agent: Agent) async throws

    /// Get session state for an agent
    func sessionState(for agent: Agent, sessionId: UUID) async throws -> AnyCodable?

    /// Update session state for an agent
    func updateSessionState(_ state: AnyCodable, for agent: Agent, sessionId: UUID) async throws
}
